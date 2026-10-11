"""ADR-0072 / T07：判断题闭环（出题-判定-引导）单测。

出题改走**运行时**（出题助手，见 ``_quiz_generate_stream``），与普通出题同源：资料库检索 /
学科提示 / 溯源引用 / 工具信封全部生效；**判定与讲解一律走 LLM**——待判定题目连同
正确答案注入 tutor 上下文，由模型就本题生成反馈。

- 出题：经 ``rt.run(question)`` 产判断题 → 题卡剥离答案/解析后下发（不提前泄题）→ 写 pending_quiz。
- 判定：待判定态被**消费一次**（正确答案落进会话历史）→ 信号归一化产出 ``quiz_judge``
  动作（清单归属 tutor）→ 题目与答案经 ``ctx.extra["pending_quiz"]`` 交给模型。服务端不再有
  yes/no 词典，也不再保留 attempts 状态机；定向不再靠「路由算完再改判」。
"""
import asyncio
import uuid
from collections.abc import AsyncIterator
from types import SimpleNamespace

from sqlmodel import select

from agent_core.ports import RuntimeDeps
from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_DONE,
    EVENT_ERROR,
    EVENT_RUN_STARTED,
    EVENT_STEP,
    EVENT_THINKING,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
    EVENT_USER_MESSAGE,
    assistant_message,
    data_event,
    done,
    run_started,
    step,
    thinking,
    tool_call,
    tool_result,
    user_message,
)
from agent_core.runtime import RouteDecision
from agent_core.subagent import SubAgentContext
from app.db.models import Conversation, Message
from app.db.models.material import KnowledgePoint
from app.features.assistant.schemas import AssistantChatReq, CoursewareContext
from app.features.assistant.service import (
    _consume_pending_quiz,
    _judge_answer_bool,
    _quiz_generate_stream,
    chat,
)
from tests.utils.fake_provider import FakeLLMProvider

# 运行时会话可能出现的全部帧类型（出题段 + 收尾）。任何新帧类型都会让
# 「无新帧类型」的断言失败——判断题闭环不得靠新协议帧做事。
_KNOWN_FRAME_TYPES = {
    EVENT_RUN_STARTED,
    EVENT_USER_MESSAGE,
    EVENT_THINKING,
    EVENT_ASSISTANT_MESSAGE,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
    EVENT_STEP,
    EVENT_DATA,
    EVENT_DONE,
    EVENT_ERROR,
}


def test_judge_answer_bool_normalizes():
    """出题侧仍要把模型的答案文本收口成布尔（存进 pending_quiz 供模型判定用）。"""
    assert _judge_answer_bool("对") is True
    assert _judge_answer_bool("错") is False
    assert _judge_answer_bool("错误") is False
    assert _judge_answer_bool("") is True  # 兜底收口为真，避免答案判定整体崩坏


# ── 出题：经运行时（出题助手），与普通出题同源 ──────────────────────────────────
#
# 判断题出题不再直连裸出题管线，改走 rt.run(question)：资料库检索 / 学科提示 /
# 溯源引用 / 工具信封全部同源。题面剥离答案与写待判定态仍由 service 负责。


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


def _kp_fixture(db, tid) -> KnowledgePoint:
    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name="轴对称"
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)
    return kp


def _judge_card(answer: str = "错") -> dict:
    return {
        "subject": "数学",
        "grade": 4,
        "knowledge_point": "轴对称",
        "qtype": "choice",
        "stem": "平行四边形是轴对称图形",
        "options": ["对", "错"],
        "answer": answer,
        "explanation": "平行四边形两组对边平行且相等，但不是轴对称图形。",
        "reasoning": "先确认考查点",
        "difficulty": "easy",
        "semester": "下学期",
    }


class _QuizRuntime:
    """桩 runtime：产出与出题助手同形的帧序列（含**未剥离**答案的题卡）。

    service 必须自己完成剥离与写待判定态——替身故意下发带答案的题卡，用以证明剥离
    确实发生在 service 侧（而不是「管线本来就不给答案」）。同时记录 business 与
    ``ctx.extra``，验证判断题规格（judge=True）确实投给了出题助手。
    """

    def __init__(self, *, emit_card=True, finish_text=None, error=None) -> None:
        self.business = None
        self.extra = None
        self.message = None
        self.emit_card = emit_card
        self.finish_text = finish_text or (
            "已生成 1 道题，题卡中包含题目、选项与解析，可据此布置给学生。"
        )
        self.error = error

    async def run(self, message, *, role, ctx, deps, business=None, session=None):
        self.business = business
        self.extra = ctx.extra
        self.message = message
        yield run_started()
        yield user_message(message)
        yield thinking("正在理解你的需求，并选择最合适的助手…", extra={"routing": True})
        yield thinking("已选择助手：出题助手", extra={"routing": True})
        yield tool_call("generate_question", label="出题")
        yield step("正在为《数学》4年级「轴对称」出选择题…")
        yield thinking("先确认考查点")
        if self.error is not None:
            yield self.error
            yield done(ctx.extra.get("session_id"))
            return
        if self.emit_card:
            yield data_event(_judge_card(), extra={"type": "question"})
        yield tool_result("generate_question", {"count": 1})
        yield assistant_message(self.finish_text)
        yield done(ctx.extra.get("session_id"))


def _deps() -> RuntimeDeps:
    return RuntimeDeps(provider=FakeLLMProvider())


def _run_quiz(db, *, rt, req, conv_id, teacher_id):
    ctx = SubAgentContext(
        role="teacher", message=req.message, extra={"session_id": str(conv_id)}
    )
    return asyncio.run(
        _drain(
            _quiz_generate_stream(
                session=db, conv_id=conv_id, req=req, teacher_id=teacher_id,
                rt=rt, deps=_deps(), role="teacher", ctx=ctx, business="question",
            )
        )
    )


def _quiz_req(kp_id) -> AssistantChatReq:
    return AssistantChatReq(
        message="出一道判断题",
        courseware=CoursewareContext(knowledge_point_id=kp_id),
        quiz=True,
    )


def test_quiz_generate_runs_via_runtime_and_strips_answer(db):
    """出题经运行时：帧序列带 USER_MESSAGE + 两条路由 THINKING（旧直连管线没有这些）。"""
    tid = _teacher_id()
    kp = _kp_fixture(db, tid)
    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    rt = _QuizRuntime()

    frames = _run_quiz(
        db, rt=rt, req=_quiz_req(kp.id), conv_id=conv_id, teacher_id=tid
    )
    types = [f.eventType for f in frames]

    # 经运行时的证据：用户消息帧 + 路由思考帧。
    assert EVENT_USER_MESSAGE in types
    routed = [
        f for f in frames
        if f.eventType == EVENT_THINKING and (f.extra or {}).get("routing")
    ]
    assert len(routed) == 2
    # 无新帧类型：判断题闭环不靠新协议帧做事。
    assert set(types) <= _KNOWN_FRAME_TYPES

    # 判断题规格（judge=True）投给出题助手；业务由预航班决策给出。
    assert rt.business == "question"
    assert rt.extra["specs"][0]["judge"] is True
    assert rt.extra["specs"][0]["knowledge_point"] == "轴对称"

    # 题卡剥离答案 / 解析 / 推理（不提前泄题）。
    data_frames = [f for f in frames if f.eventType == EVENT_DATA]
    assert len(data_frames) == 1
    assert data_frames[0].data["type"] == "question"
    card = data_frames[0].data["result"]
    assert card["stem"] == "平行四边形是轴对称图形"
    assert card["options"] == ["对", "错"]
    assert card["answer"] == ""
    assert card["explanation"] == ""
    assert card["reasoning"] == ""

    # 正确答案布尔 + 元信息落 pending_quiz，待判定分支消费。
    pending = db.get(Conversation, conv_id).pending_quiz
    assert pending["answer"] is False
    assert pending["name"] == "轴对称"
    assert pending["answer_text"] == "错"
    assert pending["explanation"]
    assert pending["stem"] == "平行四边形是轴对称图形"


def test_quiz_generate_replaces_generic_finish_with_quiz_intro(db):
    """成题后：出题助手的通用收尾（讲「含解析 / 可布置给学生」）适用于整卷出题，
    但不适用于判断题闭环（题面已剥答案）。改用闭环自带的题面引导，避免文案撒谎。
    """
    tid = _teacher_id()
    kp = _kp_fixture(db, tid)
    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)

    frames = _run_quiz(
        db, rt=_QuizRuntime(), req=_quiz_req(kp.id), conv_id=conv_id, teacher_id=tid
    )
    msgs = [f.text or "" for f in frames if f.eventType == EVENT_ASSISTANT_MESSAGE]
    assert any("轴对称" in t and "判断题" in t for t in msgs)
    assert not any("可据此布置给学生" in t for t in msgs)


def test_quiz_generate_surfaces_finish_when_no_card(db):
    """无题卡（生成失败 / 未配置模型）：出题助手的收尾原因原样透传，不写待判定态。"""
    tid = _teacher_id()
    kp = _kp_fixture(db, tid)
    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    rt = _QuizRuntime(emit_card=False, finish_text="未配置 AI 出题引擎，无法生成题目。")

    frames = _run_quiz(
        db, rt=rt, req=_quiz_req(kp.id), conv_id=conv_id, teacher_id=tid
    )
    text = "".join(f.text or "" for f in frames if f.eventType == EVENT_ASSISTANT_MESSAGE)
    assert "未配置 AI 出题引擎" in text
    assert not any(f.eventType == EVENT_DATA for f in frames)
    assert db.get(Conversation, conv_id).pending_quiz is None


def test_quiz_generate_forwards_runtime_error_frame(db):
    """运行时把厂商拒绝转成 ERROR 帧：出题入口原样转发，不吞掉。"""
    from agent_core.protocol import error as _error

    tid = _teacher_id()
    kp = _kp_fixture(db, tid)
    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    rt = _QuizRuntime(
        emit_card=False,
        error=_error("API Key 无效，请重新填写。", code="PROVIDER_ERROR"),
    )

    frames = _run_quiz(
        db, rt=rt, req=_quiz_req(kp.id), conv_id=conv_id, teacher_id=tid
    )
    errs = [f for f in frames if f.eventType == EVENT_ERROR]
    assert len(errs) == 1
    assert errs[0].code == "PROVIDER_ERROR"
    assert "API Key" in errs[0].message  # 策展提示，不泄露原始报文


def test_quiz_generate_missing_kp_context_hints(db):
    """缺知识点上下文：不下发题卡、写干净提示，且**不触达运行时**。"""
    tid = _teacher_id()
    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    rt = _QuizRuntime()
    req = AssistantChatReq(message="出一道判断题", quiz=True)

    frames = _run_quiz(db, rt=rt, req=req, conv_id=conv_id, teacher_id=tid)
    text = "".join(f.text or "" for f in frames if f.eventType == EVENT_ASSISTANT_MESSAGE)
    assert "知识点上下文" in text
    assert rt.extra is None  # 未触达运行时
    assert not any(f.eventType == EVENT_DATA for f in frames)


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
    """桩 runtime：记录本轮路由、收到的信号与 ctx.extra，产出一句可判定回复。

    T06 起定向迁进信号：服务端在归一化阶段给出 ``action=quiz_judge``，桩按清单归属
    把该动作映射到 tutor（真路由由 ``test_intent_routing_contract`` 覆盖）。
    """

    def __init__(self) -> None:
        self.business = None
        self.extra = None
        self.signal = None

    def name_of(self, business: str) -> str:
        return {"tutor": "伴学答疑", "query": "资料查询"}.get(business, business)

    async def decide(self, signal, *, role: str, deps) -> RouteDecision:
        self.signal = signal
        if getattr(signal, "action", None) == "quiz_judge":
            return RouteDecision(business="tutor", name="伴学答疑")
        # 非待判定态：刻意给 query，反衬 quiz_judge 动作才把方向扳到 tutor。
        return RouteDecision(business="query", name="资料查询")

    async def run(
        self, message, *, role, ctx, deps, business=None, session=None
    ) -> AsyncIterator:
        self.business = business
        self.extra = ctx.extra
        yield assistant_message("（模型就本题给出的反馈）")
        yield done(ctx.extra.get("session_id"))


def test_pending_quiz_routes_to_llm_instead_of_deterministic_reply(db):
    """待判定态不再短路成硬编码文案：信号定向 quiz_judge→tutor，题目与答案注入 ctx.extra。"""
    tid = _teacher_id()
    conv_id = uuid.uuid4()
    conv = _conv(db, teacher_id=tid, conv_id=conv_id)
    _pending_fixture(db, conv=conv, answer=True)

    rt = _CaptureRuntime()
    caller = SimpleNamespace(
        role="teacher",
        user=SimpleNamespace(id=tid, teacher_id=tid, class_id=None, grade=0),
    )
    req = AssistantChatReq(message="错", session_id=str(conv_id))

    frames = asyncio.run(
        _drain_chat(chat(caller=caller, req=req, session=db, runtime=rt))
    )
    assert any("DONE" in f for f in frames)
    # 模型被真正调用（桩 run 产出正文）；定向经信号（action=quiz_judge）交讲解而非只读检索。
    assert getattr(rt.signal, "action", None) == "quiz_judge"
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
