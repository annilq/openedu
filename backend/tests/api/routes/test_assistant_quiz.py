"""ADR-0072 判断题闭环：端到端（经 SSE 端点）单测。

monkeypatch 掉真实出题 LLM，验证：
- quiz=true + 课件上下文 → SSE 下发题卡，答案/解析已剥离（不提前泄题）。
- 续接同一会话作答 → 待判定态被消费，路由强制到 tutor，题目 + 正确答案随
  ctx.extra 交给模型（判定与讲解都由 LLM 产出，服务端不留确定性分支）。

同时锁定 SSE 序列化收口（chat 的 quiz 分支必须 yield ev.to_sse()，而非裸对象）。
"""
import json
import uuid

from sqlmodel import select

from agent_core.protocol import assistant_message, done
from agent_core.runtime import RouteDecision
from app.db.models import Conversation, User
from app.db.models.material import KnowledgePoint
from app.domain.provider import GeneratedQuestion
from tests.utils.user import auth_headers, register_teacher


async def _fake_generate_question(provider, *, subject, grade, knowledge_point, qtype, difficulty, semester="", **kwargs):
    return GeneratedQuestion(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        stem="平行四边形是轴对称图形", options=["对", "错"], answer="错",
        explanation="平行四边形不是轴对称图形。", difficulty=difficulty, semester=semester,
    )


def _parse_sse(text):
    out = []
    for line in text.split("\n"):
        line = line.strip()
        if line.startswith("data: "):
            out.append(json.loads(line[len("data: "):]))
    return out


def _teacher_id(db, username: str) -> uuid.UUID:
    return db.exec(select(User).where(User.username == username)).one().id


def _make_kp(db, *, tid, name="轴对称"):
    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name=name
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)
    return kp


def _stream(client, token, body):
    with client.stream(
        "POST",
        "/api/v1/assistant/chat",
        headers={**auth_headers(token), "Accept": "text/event-stream"},
        json=body,
    ) as resp:
        status = resp.status_code
        events = _parse_sse("".join(resp.iter_text()))
    return status, events


def test_quiz_chat_emits_stripped_question_card(client, db, monkeypatch):
    """出题：SSE 下发题卡且答案/解析已剥离（不提前泄题）。"""
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _fake_generate_question
    )
    r = register_teacher(client, username="qz_teacher")
    token = r.json()["access_token"]
    tid = _teacher_id(db, "qz_teacher")
    kp = _make_kp(db, tid=tid)

    status, events = _stream(
        client, token,
        {
            "message": "出一道判断题",
            "quiz": True,
            "courseware": {
                "knowledge_point_id": str(kp.id),
                "subject": "数学", "grade": 4, "semester": "下学期",
                "knowledge_point": "轴对称",
            },
        },
    )
    assert status == 200, events
    types = [e["eventType"] for e in events]
    assert "DONE" in types
    # SSE 序列化收口正确：每个帧都是 dict（data: {...}），不是裸对象 repr。
    assert all(isinstance(e, dict) for e in events)

    questions = [
        e["data"]["result"]
        for e in events
        if e["eventType"] == "DATA" and e["data"].get("type") == "question"
    ]
    assert len(questions) == 1
    q = questions[0]
    assert q["stem"] == "平行四边形是轴对称图形"
    assert q["answer"] == ""
    assert q["explanation"] == ""


class _StubRuntime:
    """桩 runtime：记录本轮路由与 ctx.extra，产出固定一句（替掉真实 LLM）。"""

    def __init__(self) -> None:
        self.business = None
        self.extra = None

    def name_of(self, business: str) -> str:
        return {"tutor": "伴学答疑"}.get(business, business)

    async def decide(self, message, *, role, deps):
        # 刻意给 query：证明待判定态会把路由**强制**扳到 tutor。
        return RouteDecision(business="query", name="资料查询")

    async def run(self, message, *, role, ctx, deps, business=None, session=None):
        self.business = business
        self.extra = ctx.extra
        yield assistant_message("（模型判定反馈）")
        yield done(ctx.extra.get("session_id"))


def _ask_quiz(client, token, kp_id) -> str:
    """首轮：出一道判断题，返回会话 id。"""
    _status, events = _stream(
        client, token,
        {
            "message": "出一道判断题",
            "quiz": True,
            "courseware": {"knowledge_point_id": str(kp_id)},
        },
    )
    return [e for e in events if e["eventType"] == "DONE"][-1]["session_id"]


def _pending_cleared(db, sid: str) -> bool:
    return db.get(Conversation, uuid.UUID(sid)).pending_quiz is None


def test_quiz_judge_routes_to_llm_and_consumes_pending(client, db, monkeypatch):
    """判定走 LLM：不是服务端拼硬编码文案，而是路由到 tutor 并带上题目与正确答案。"""
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _fake_generate_question
    )
    rt = _StubRuntime()
    monkeypatch.setattr("app.features.assistant.service.get_runtime", lambda: rt)

    r = register_teacher(client, username="qz2_teacher")
    token = r.json()["access_token"]
    tid = _teacher_id(db, "qz2_teacher")
    kp = _make_kp(db, tid=tid)
    sid = _ask_quiz(client, token, kp.id)
    assert sid, "首轮 DONE 帧应回写会话 id"

    status2, judge_events = _stream(client, token, {"message": "错", "session_id": sid})
    assert status2 == 200, judge_events
    answer = "".join(
        e.get("text", "") for e in judge_events if e["eventType"] == "ASSISTANT_MESSAGE"
    )
    # 模型被真正调用（桩产出正文）；旧的确定性分支不会走到模型。
    assert "（模型判定反馈）" in answer
    assert rt.business == "tutor"
    pending = (rt.extra or {}).get("pending_quiz") or {}
    assert pending.get("stem") == "平行四边形是轴对称图形"
    assert pending.get("answer") is False  # 真答案为「错」，随上下文交给模型
    # 待判定态只消费一次：清空后下一轮不再被拦截。
    assert _pending_cleared(db, sid)


def test_quiz_ambiguous_also_routes_to_llm(client, db, monkeypatch):
    """含糊回答同样交给模型（不再有「请用对/错回答」的确定性兜底）。"""
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _fake_generate_question
    )
    rt = _StubRuntime()
    monkeypatch.setattr("app.features.assistant.service.get_runtime", lambda: rt)

    r = register_teacher(client, username="qz3_teacher")
    token = r.json()["access_token"]
    tid = _teacher_id(db, "qz3_teacher")
    kp = _make_kp(db, tid=tid)
    sid = _ask_quiz(client, token, kp.id)

    status2, judge_events = _stream(
        client, token, {"message": "这题我不会", "session_id": sid}
    )
    assert status2 == 200, judge_events
    answer = "".join(
        e.get("text", "") for e in judge_events if e["eventType"] == "ASSISTANT_MESSAGE"
    )
    assert "（模型判定反馈）" in answer
    assert rt.business == "tutor"
    assert _pending_cleared(db, sid)
