"""ADR-0072：判断题闭环（出题-判定-引导）单测。

出题复用 question 管线（monkeypatch 掉真实 LLM）；**判定与讲解一律走 LLM**——
待判定题目连同正确答案注入 tutor 上下文，由模型就本题生成反馈。

- 出题：生成判断题 → 题卡剥离答案/解析后下发（不提前泄题）→ 写 pending_quiz。
- 判定：待判定态被**消费一次**（正确答案落进会话历史）→ 路由强制扳到 tutor
  → 题目与答案经 ``ctx.extra["pending_quiz"]`` 交给模型。服务端不再有 yes/no
  词典，也不再保留 attempts 状态机。
"""
import asyncio
import uuid
from collections.abc import AsyncIterator
from types import SimpleNamespace

from sqlmodel import select

from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_DONE,
    EVENT_ERROR,
    EVENT_RUN_STARTED,
    assistant_message,
    done,
)
from agent_core.runtime import RouteDecision
from app.db.models import Conversation, Message
from app.db.models.material import KnowledgePoint
from app.domain.provider import GeneratedQuestion
from app.features.assistant.schemas import AssistantChatReq, CoursewareContext
from app.features.assistant.service import (
    _consume_pending_quiz,
    _judge_answer_bool,
    _quiz_generate_stream,
    chat,
)


def test_judge_answer_bool_normalizes():
    """出题侧仍要把模型的答案文本收口成布尔（存进 pending_quiz 供模型判定用）。"""
    assert _judge_answer_bool("对") is True
    assert _judge_answer_bool("错") is False
    assert _judge_answer_bool("错误") is False
    assert _judge_answer_bool("") is True  # 兜底收口为真，避免答案判定整体崩坏


# ── 出题（monkeypatch 掉真实 LLM） ──────────────────────────────────────────────


async def _fake_generate_question(provider, *, subject, grade, knowledge_point, qtype, difficulty, semester="", **kwargs):
    """替身：恒定返回一道「平行四边形是轴对称图形 → 错」的判断题。"""
    return GeneratedQuestion(
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        stem="平行四边形是轴对称图形",
        options=["对", "错"],
        answer="错",
        explanation="平行四边形两组对边平行且相等，但不是轴对称图形。",
        difficulty=difficulty,
        semester=semester,
    )


async def _drain(gen: AsyncIterator) -> list:
    frames: list = []
    async for f in gen:
        frames.append(f)
    return frames


def _teacher_id() -> uuid.UUID:
    return uuid.uuid4()


def _conv(db, *, teacher_id, conv_id: uuid.UUID) -> Conversation:
    conv = Conversation(
        id=conv_id,
        kind="agent",
        teacher_id=teacher_id,
        student_id=None,
        model=None,
        title="出题",
        status="running",
    )
    db.add(conv)
    db.commit()
    return conv


class _ConfiguredProvider:
    """测试桩：模拟「已配置可用模型」的 provider（真实 GenkitProvider 的极小替身）。"""

    configured = True


def test_quiz_generate_strips_answer_and_writes_pending(db, monkeypatch):
    """出题：题卡剥离答案/解析后下发（不提前泄题），pending_quiz 写入正确答案与元信息。"""
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _fake_generate_question
    )
    tid = _teacher_id()
    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name="轴对称"
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)

    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    req = AssistantChatReq(
        message="出一道判断题",
        courseware=CoursewareContext(knowledge_point_id=kp.id),
        quiz=True,
    )

    frames = asyncio.run(
        _drain(
            _quiz_generate_stream(
                session=db, conv_id=conv_id, req=req, teacher_id=tid,
                provider=_ConfiguredProvider(),
            )
        )
    )
    types = [f.eventType for f in frames]
    assert EVENT_RUN_STARTED in types
    assert EVENT_DONE in types
    assert frames[-1].session_id == str(conv_id)

    data_frames = [f for f in frames if f.eventType == EVENT_DATA]
    assert len(data_frames) == 1
    card = data_frames[0].data["result"]
    assert data_frames[0].data["type"] == "question"
    # 题面照发，但答案 / 解析 / 推理被剥离，不能提前泄题。
    assert card["stem"] == "平行四边形是轴对称图形"
    assert card["options"] == ["对", "错"]
    assert card["answer"] == ""
    assert card["explanation"] == ""
    assert card["reasoning"] == ""

    # 正确答案布尔 + 元信息落 pending_quiz，待判定分支消费。
    conv = db.get(Conversation, conv_id)
    pending = conv.pending_quiz
    assert pending["answer"] is False
    assert pending["name"] == "轴对称"
    assert pending["answer_text"] == "错"
    assert pending["explanation"]


class _UnconfiguredProvider:
    """测试桩：模拟「未配置可用模型」的 provider（configured=False）。"""

    configured = False


def test_quiz_generate_unconfigured_provider_emits_hint(db):
    """未配置模型：出题入口应下发干净的「未配置模型」提示，而非放出去撞 401。"""
    tid = _teacher_id()
    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name="轴对称"
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)

    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    req = AssistantChatReq(
        message="出一道判断题",
        courseware=CoursewareContext(knowledge_point_id=kp.id),
        quiz=True,
    )

    frames = asyncio.run(
        _drain(
            _quiz_generate_stream(
                session=db, conv_id=conv_id, req=req, teacher_id=tid,
                provider=_UnconfiguredProvider(),
            )
        )
    )
    types = [f.eventType for f in frames]
    assert EVENT_RUN_STARTED in types
    assert EVENT_DONE in types
    text = "".join(f.text for f in frames if f.eventType == EVENT_ASSISTANT_MESSAGE)
    assert "尚未配置可用的模型" in text
    # 未配置时不应触达 generate_question，也不应产出题卡。
    assert not any(f.eventType == EVENT_DATA for f in frames)


async def _boom_generate_question(provider, *, subject, grade, knowledge_point, qtype, difficulty, semester="", **kwargs):
    """替身：恒定抛 ProviderRequestError（模拟 API key 失效 / 厂商拒绝）。"""
    from agent_core.errors import ProviderRequestError

    raise ProviderRequestError("auth failed", kind="auth")


def test_quiz_generate_provider_failure_surfaced_as_error_frame(db, monkeypatch):
    """provider 鉴权失败：必须转成 SSE ERROR 帧，不得让异常穿透生成器导致流被截断。"""
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _boom_generate_question
    )
    tid = _teacher_id()
    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name="轴对称"
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)

    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    req = AssistantChatReq(
        message="出一道判断题",
        courseware=CoursewareContext(knowledge_point_id=kp.id),
        quiz=True,
    )

    frames = asyncio.run(
        _drain(
            _quiz_generate_stream(
                session=db, conv_id=conv_id, req=req, teacher_id=tid,
                provider=_ConfiguredProvider(),
            )
        )
    )
    types = [f.eventType for f in frames]
    assert EVENT_RUN_STARTED in types
    assert EVENT_DONE in types
    error_frames = [f for f in frames if f.eventType == EVENT_ERROR]
    assert len(error_frames) == 1
    assert error_frames[0].code == "PROVIDER_ERROR"
    assert "API Key" in error_frames[0].message  # 策展提示，不泄露原始报文


# ── 判定 / 讲解走 LLM ──────────────────────────────────────────────────────────


def _pending_fixture(db, *, conv, answer=True) -> dict:
    pending = {
        "answer": answer,
        "subject": "数学", "grade": 4, "semester": "下学期", "name": "轴对称",
        "stem": "平行四边形是轴对称图形", "options": ["对", "错"],
        "answer_text": "对" if answer else "错",
        "explanation": "（解析）",
    }
    conv.pending_quiz = pending
    db.add(conv)
    db.commit()
    return pending


def _msgs(db, conv_id):
    return list(
        db.exec(
            select(Message)
            .where(Message.conversation_id == conv_id)
            .order_by(Message.turn.asc())
        ).all()
    )


def test_consume_pending_quiz_clears_state_and_records_answer(db):
    """消费待判定态：返回题目字典、清空 pending_quiz，正确答案落进历史供后续轮次用。"""
    tid = _teacher_id()
    conv_id = uuid.uuid4()
    conv = _conv(db, teacher_id=tid, conv_id=conv_id)
    _pending_fixture(db, conv=conv, answer=False)

    pending = _consume_pending_quiz(session=db, conversation=conv, conv_id=conv_id)
    assert pending is not None and pending["answer"] is False
    assert db.get(Conversation, conv_id).pending_quiz is None

    quiz_msgs = [m for m in _msgs(db, conv_id) if m.step == "quiz_answer"]
    assert len(quiz_msgs) == 1 and "错" in quiz_msgs[0].content

    # 幂等：再消费一次为空，不会重复往历史里写答案。
    assert _consume_pending_quiz(session=db, conversation=conv, conv_id=conv_id) is None
    assert len([m for m in _msgs(db, conv_id) if m.step == "quiz_answer"]) == 1


def test_quiz_hint_context_carries_question_answer_and_rules():
    """待判定上下文：题目 + 正确答案 + 判定/讲解口径一起进 prompt。"""
    from app.ai.subagents.tutor.agent import _quiz_hint_context

    pending = {
        "answer": False, "name": "轴对称", "stem": "平行四边形是轴对称图形",
        "options": ["对", "错"], "explanation": "（解析）",
    }
    text = _quiz_hint_context(pending, "已有上下文")
    assert "已有上下文" in text  # 不覆盖既有上下文，拼在后面
    assert "平行四边形是轴对称图形" in text
    assert "正确答案：错" in text  # 模型拿得到答案才谈得上「判」
    assert "讲解" in text  # 求讲解 → 揭示答案这条口径在 prompt 里


class _CaptureRuntime:
    """桩 runtime：记录 run 收到的 business 与 ctx.extra，产出一句可判定回复。"""

    def __init__(self) -> None:
        self.business = None
        self.extra = None

    def name_of(self, business: str) -> str:
        return {"tutor": "伴学答疑", "query": "资料查询"}.get(business, business)

    async def decide(self, message: str, *, role: str, deps) -> RouteDecision:
        # 刻意给 query：证明待判定态会把路由**强制**扳到 tutor，而不是照单全收。
        return RouteDecision(business="query", name="资料查询")

    async def run(
        self, message, *, role, ctx, deps, business=None, session=None
    ) -> AsyncIterator:
        self.business = business
        self.extra = ctx.extra
        yield assistant_message("（模型就本题给出的反馈）")
        yield done(ctx.extra.get("session_id"))


def test_pending_quiz_routes_to_llm_instead_of_deterministic_reply(db):
    """待判定态不再短路成硬编码文案：消费后强制 tutor，题目与答案注入 ctx.extra。"""
    tid = _teacher_id()
    conv_id = uuid.uuid4()
    conv = _conv(db, teacher_id=tid, conv_id=conv_id)
    _pending_fixture(db, conv=conv, answer=True)

    rt = _CaptureRuntime()
    caller = SimpleNamespace(
        role="teacher",
        user=SimpleNamespace(id=tid, teacher_id=tid, grade=0),
    )
    req = AssistantChatReq(message="错", session_id=str(conv_id))

    frames = asyncio.run(
        _drain_chat(chat(caller=caller, req=req, session=db, runtime=rt))
    )
    assert any("DONE" in f for f in frames)
    # 模型被真正调用（桩 run 产出正文），且路由被扳到讲解而非只读检索。
    assert rt.business == "tutor"
    assert any("（模型就本题给出的反馈）" in f for f in frames)

    pending = (rt.extra or {}).get("pending_quiz")
    assert isinstance(pending, dict)
    assert pending["stem"] == "平行四边形是轴对称图形"
    assert pending["answer"] is True  # 正确答案随上下文交给模型

    # 消费：pending_quiz 清空，正确答案入历史（后续轮次仍可判定）。
    assert db.get(Conversation, conv_id).pending_quiz is None
    assert any(m.step == "quiz_answer" for m in _msgs(db, conv_id))


async def _drain_chat(chat_coro) -> list[str]:
    """``chat`` 是 async def 返回异步生成器：先 await 取生成器再迭代。"""
    gen = await chat_coro
    frames: list[str] = []
    async for frame in gen:
        frames.append(frame)
    return frames
