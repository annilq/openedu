"""ADR-0072 / T07 判断题闭环：端到端（经 SSE 端点）单测。

覆盖：

- 出题（``quiz=true`` + 课件上下文）经**运行时**（出题助手）出判断题：SSE 出现
  ``USER_MESSAGE`` + 两条路由 ``THINKING``（旧直连管线没有这些帧），题卡的答案 / 解析
  已剥离（不提前泄题），正确答案落 ``pending_quiz``。
- 续接同一会话作答 → 待判定态被消费，信号归一化定向 ``quiz_judge``（→tutor），题目 +
  正确答案随 ctx.extra 交给模型（判定与讲解都由 LLM 产出，服务端不留确定性分支）。

同时锁定 SSE 序列化收口（chat 的 quiz 分支必须 yield ev.to_sse()，而非裸对象）。
"""
import json
import uuid

from sqlmodel import select

from agent_core.protocol import (
    assistant_message,
    data_event,
    done,
    run_started,
    thinking,
    user_message,
)
from agent_core.runtime import RouteDecision
from app.db.models import Conversation, User
from app.db.models.material import KnowledgePoint
from tests.utils.user import auth_headers, register_teacher

# 运行时会话可能出现（并被前端识别）的全部帧类型。任何新帧类型都会让「无新帧类型」
# 的断言失败——判断题闭环不得靠新协议帧做事。
_KNOWN_FRAME_TYPES = {
    "RUN_STARTED",
    "USER_MESSAGE",
    "THINKING",
    "ASSISTANT_MESSAGE",
    "TOOL_CALL",
    "TOOL_RESULT",
    "STEP",
    "DATA",
    "ERROR",
    "DONE",
}


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


def test_quiz_chat_runs_via_runtime_and_strips_question_card(client, db):
    """出题经运行时（出题助手）：SSE 出现 USER_MESSAGE + 路由 THINKING，题卡剥离答案/解析。

    真实 runtime + 确定性替身 LLM：题卡由出题 subagent 产出（与普通出题同一路径），
    故断言的「经运行时」证据（用户消息帧 / 路由思考帧）真实反映编排形态。
    """
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

    # 经运行时的证据：用户消息帧 + 两条路由思考帧（旧直连管线一条都不发）。
    assert "USER_MESSAGE" in types
    routed = [
        e for e in events
        if e["eventType"] == "THINKING" and e.get("extra", {}).get("routing")
    ]
    assert len(routed) == 2
    assert any("出题助手" in e.get("text", "") for e in routed)
    # 无新帧类型：判断题闭环不引入新协议帧。
    assert set(types) <= _KNOWN_FRAME_TYPES

    questions = [
        e["data"]["result"]
        for e in events
        if e["eventType"] == "DATA" and e["data"].get("type") == "question"
    ]
    assert len(questions) == 1
    q = questions[0]
    # 题面照发，但答案 / 解析 / 推理被剥离（不提前泄题）。
    assert q["stem"] == "这是一道测试题的题干，用于测试替身产出。"
    assert q["answer"] == ""
    assert q["explanation"] == ""
    assert q["reasoning"] == ""

    # 正确答案（替身答案「B」按兜底收口为真）+ 元信息落 pending_quiz。
    sid = [e for e in events if e["eventType"] == "DONE"][-1]["session_id"]
    pending = db.get(Conversation, uuid.UUID(sid)).pending_quiz
    assert pending and pending["stem"] == q["stem"]
    assert pending["answer"] is True


# 判断题规格产出的替身题卡（未剥离答案）：service 必须负责剥离。
_STUB_CARD = {
    "subject": "数学", "grade": 4, "knowledge_point": "轴对称",
    "qtype": "choice", "stem": "平行四边形是轴对称图形", "options": ["对", "错"],
    "answer": "错", "explanation": "平行四边形不是轴对称图形。",
    "reasoning": "先确认考查点", "difficulty": "easy", "semester": "下学期",
}


class _StubRuntime:
    """桩 runtime：生成轮产出题卡（写 pending_quiz），作答轮把方向交给 tutor。

    T06/T07 起定向迁进信号：服务端在归一化阶段给 ``quiz_generate`` / ``quiz_judge``，
    桩按动作把生成 / 判定分派到 question / tutor（真路由由 ``test_intent_routing_contract``
    覆盖）。
    """

    def __init__(self) -> None:
        self.business = None
        self.extra = None
        self.signal = None

    def name_of(self, business: str) -> str:
        return {"tutor": "伴学答疑", "question": "出题助手"}.get(business, business)

    async def decide(self, signal, *, role, deps):
        self.signal = signal
        action = getattr(signal, "action", None)
        if action == "quiz_judge":
            return RouteDecision(business="tutor", name="伴学答疑")
        if action == "quiz_generate":
            return RouteDecision(business="question", name="出题助手")
        # 非待判定态：刻意给 query，证明 quiz_judge/quiz_generate 动作才把方向扳对。
        return RouteDecision(business="query", name="资料查询")

    async def run(self, message, *, role, ctx, deps, business=None, session=None):
        self.business = business
        self.extra = ctx.extra
        if business == "question":
            yield run_started()
            yield user_message(message)
            yield thinking("正在理解你的需求，并选择最合适的助手…", extra={"routing": True})
            yield thinking("已选择助手：出题助手", extra={"routing": True})
            yield data_event(_STUB_CARD, extra={"type": "question"})
            yield assistant_message(
                "已生成 1 道题，题卡中包含题目、选项与解析，可据此布置给学生。"
            )
            yield done(ctx.extra.get("session_id"))
            return
        yield assistant_message("（模型判定反馈）")
        yield done(ctx.extra.get("session_id"))


def _ask_quiz(client, token, kp_id) -> str:
    """首轮：经运行时出一道判断题，返回会话 id。"""
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
    # 模型被真正调用（桩产出正文）；定向经信号（action=quiz_judge）交讲解而非只读检索。
    assert "（模型判定反馈）" in answer
    assert getattr(rt.signal, "action", None) == "quiz_judge"
    assert rt.business == "tutor"
    pending = (rt.extra or {}).get("pending_quiz") or {}
    assert pending.get("stem") == "平行四边形是轴对称图形"
    assert pending.get("answer") is False  # 真答案为「错」，随上下文交给模型
    # 待判定态只消费一次：清空后下一轮不再被拦截。
    assert _pending_cleared(db, sid)


def test_quiz_ambiguous_also_routes_to_llm(client, db, monkeypatch):
    """含糊回答同样交给模型（不再有「请用对/错回答」的确定性兜底）。"""
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
