"""ADR-0089 判断题闭环：端到端（经 SSE 端点）单测。

「答案进历史」形态，服务端不再有出题/判定分支：

- 出题：纯文本（含「判断题」）+ 课件上下文 → **文本路由**落到出题助手（不再有
  ``quiz_generate`` 动作键 / ``quiz=true`` 旗标）→ 题卡**连答案一起**下发并落库
  （不再剥离、不再写 ``pending_quiz``）。
- 判定：续接同一会话作答 → 由 tutor 承接；题目与答案经**对话历史**（题卡渲染进
  assistant content）进入模型上下文，判定与讲解都由 LLM 产出。
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
from app.db.models import Conversation, Message, User
from app.db.models.material import KnowledgePoint
from tests.utils.user import auth_headers, register_teacher

# 运行时会话可能出现（并被前端识别）的全部帧类型白名单。判断题闭环（ADR-0090）自身
# 不引入新帧；但 03(a) 回复后 follow-up 引入了全局 SUGGESTED_ACTIONS 帧（每条回复后下发、
# 不落库），须列入白名单。新增其它帧类型须显式评估后再放宽此处。
_KNOWN_FRAME_TYPES = {
    "RUN_STARTED",
    "USER_MESSAGE",
    "THINKING",
    "ASSISTANT_MESSAGE",
    "TOOL_CALL",
    "TOOL_RESULT",
    "STEP",
    "SUGGESTED_ACTIONS",
    "DATA",
    "ERROR",
    "DONE",
}

# 出题助手产出的判断题卡（judge=True，**含答案**）：原样下发 / 落库。
_STUB_CARD = {
    "subject": "数学",
    "grade": 4,
    "knowledge_point": "轴对称",
    "qtype": "choice",
    "stem": "平行四边形是轴对称图形",
    "options": ["对", "错"],
    "answer": "错",
    "explanation": "平行四边形两组对边平行且相等，但不是轴对称图形。",
    "reasoning": "先确认考查点",
    "difficulty": "easy",
    "semester": "下学期",
    "judge": True,
}


def _parse_sse(text):
    out = []
    for line in text.split("\n"):
        line = line.strip()
        if line.startswith("data: "):
            out.append(json.loads(line[len("data: ") :]))
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


class _JudgeLoopRuntime:
    """桩 runtime：出题轮产出含答案的判断题卡，作答轮定向 tutor 并记录历史。

    ADR-0089 起定向不再有 quiz_generate / quiz_judge 动作键：出题轮按文本路由到
    question，作答轮（「对 / 错 / 不会」）落到 tutor，判定依据是对话历史里的题卡。
    """

    def __init__(self) -> None:
        self.business = None
        self.extra = None
        self.history = None

    async def decide(self, signal, *, role, deps) -> RouteDecision:
        text = getattr(signal, "text", "") or ""
        if any(kw in text for kw in ("判断题", "出一道", "出题", "练习题")):
            return RouteDecision(business="question", name="出题助手")
        return RouteDecision(business="tutor", name="伴学答疑")

    async def run(self, message, *, role, ctx, deps, business=None, session=None):
        self.business = business
        self.extra = ctx.extra
        self.history = ctx.history
        if business == "question":
            yield run_started()
            yield user_message(message)
            yield thinking("正在理解你的需求，并选择最合适的助手…", extra={"routing": True})
            yield thinking("已选择助手：出题助手", extra={"routing": True})
            yield data_event(dict(_STUB_CARD), extra={"type": "question"})
            yield assistant_message("请判断「对」或「错」后回答。")
            yield done(ctx.extra.get("session_id"))
            return
        yield assistant_message("（模型就本题给出的判定反馈）")
        yield done(ctx.extra.get("session_id"))


def test_quiz_chat_runs_via_runtime_and_keeps_answer(client, db):
    """出题经文本路由落到出题助手：题卡**连答案一起**下发（不再剥离 / 无 pending_quiz）。

    真实 runtime + 确定性替身 LLM（``fake_llm`` autouse 夹具）：题卡由出题 subagent
    产出，故断言的「经运行时」证据（用户消息帧 / 路由思考帧）真实反映编排形态。
    """
    r = register_teacher(client, username="qz_teacher")
    token = r.json()["access_token"]
    tid = _teacher_id(db, "qz_teacher")
    kp = _make_kp(db, tid=tid)

    status, events = _stream(
        client,
        token,
        {
            "message": "请为「轴对称」出一道判断题，只展示题目和两个选项，等我回答。",
            "courseware": {
                "knowledge_point_id": str(kp.id),
                "subject": "数学",
                "grade": 4,
                "semester": "下学期",
                "knowledge_point": "轴对称",
            },
        },
    )
    assert status == 200, events
    types = [e["eventType"] for e in events]
    assert "DONE" in types
    # SSE 序列化收口正确：每个帧都是 dict（data: {...}），不是裸对象 repr。
    assert all(isinstance(e, dict) for e in events)

    # 经运行时的证据：用户消息帧 + 两条路由思考帧。
    assert "USER_MESSAGE" in types
    routed = [
        e for e in events
        if e["eventType"] == "THINKING" and e.get("extra", {}).get("routing")
    ]
    assert len(routed) == 2
    assert any("出题助手" in e.get("text", "") for e in routed)
    # 帧白名单：判断题闭环自身不引入新帧；SUGGESTED_ACTIONS 为 03(a) 全局 follow-up 帧。
    assert set(types) <= _KNOWN_FRAME_TYPES

    questions = [
        e["data"]["result"]
        for e in events
        if e["eventType"] == "DATA" and e["data"].get("type") == "question"
    ]
    assert len(questions) == 1
    q = questions[0]
    # 出题子代理自主判定 judge 规格；题面 + 答案 + 解析**全量下发**（前端隐藏待揭示）。
    assert q["judge"] is True
    assert q["answer"] == "B"
    assert q["explanation"]
    assert q["stem"]

    # 服务端再无待判定态列；题卡（含答案）随 assistant 行落库。
    sid = [e for e in events if e["eventType"] == "DONE"][-1]["session_id"]
    conv = db.get(Conversation, uuid.UUID(sid))
    assert not hasattr(conv, "pending_quiz")
    rows = db.exec(
        select(Message).where(Message.conversation_id == uuid.UUID(sid))
    ).all()
    stored = [
        c["result"]
        for m in rows
        if m.payload
        for c in (m.payload.get("cards") or [])
        if isinstance(c, dict) and c.get("type") == "question"
    ]
    assert any(c.get("judge") is True and c["answer"] == "B" for c in stored)


def _ask_quiz(client, token, kp_id) -> str:
    """首轮：经运行时的出题助手出一道判断题，返回会话 id。"""
    _status, events = _stream(
        client,
        token,
        {
            "message": "请为「轴对称」出一道判断题，只展示题目和两个选项，等我回答。",
            "courseware": {"knowledge_point_id": str(kp_id)},
        },
    )
    return [e for e in events if e["eventType"] == "DONE"][-1]["session_id"]


def test_quiz_judge_turn_reads_card_from_history(client, db, monkeypatch):
    """判定走 LLM：题目与答案经**对话历史**进模型上下文，服务端不注入待判定态。"""
    rt = _JudgeLoopRuntime()
    monkeypatch.setattr("app.features.assistant.service.get_runtime", lambda: rt)

    r = register_teacher(client, username="qz2_teacher")
    token = r.json()["access_token"]
    tid = _teacher_id(db, "qz2_teacher")
    kp = _make_kp(db, tid=tid)
    sid = _ask_quiz(client, token, kp.id)
    assert sid, "首轮 DONE 帧应回写会话 id"

    status2, judge_events = _stream(client, token, {"message": "对", "session_id": sid})
    assert status2 == 200, judge_events
    answer = "".join(
        e.get("text", "") for e in judge_events if e["eventType"] == "ASSISTANT_MESSAGE"
    )
    # 模型被真正调用（桩产出正文）；定向由文本路由落到 tutor。
    assert "（模型就本题给出的判定反馈）" in answer
    assert rt.business == "tutor"
    # 服务端不再注入待判定态：ctx.extra 里没有 pending_quiz。
    assert "pending_quiz" not in (rt.extra or {})

    # 「答案进历史」：题卡（含题干与正确答案）渲染进 assistant 的 content，
    # tutor 正是从这段历史读到答案来判定。
    assistant_turns = [
        h.get("content", "") for h in (rt.history or []) if h.get("role") == "assistant"
    ]
    assert any("平行四边形是轴对称图形" in t for t in assistant_turns)
    assert any("正确答案：错" in t for t in assistant_turns)


def test_quiz_ambiguous_also_routes_to_llm(client, db, monkeypatch):
    """含糊回答同样交给模型（不再有「请用对/错回答」的确定性兜底）。"""
    rt = _JudgeLoopRuntime()
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
    assert "（模型就本题给出的判定反馈）" in answer
    assert rt.business == "tutor"
    assert "pending_quiz" not in (rt.extra or {})
