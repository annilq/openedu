"""ADR-0089：判断题闭环（出题-判定-讲解）子代理化单测。

「答案进历史」形态：出题助手从自由文本/知识点上下文自主判定 judge 规格，题卡**连答案
一起**原样落对话历史（服务端不再剥离答案、不再维护 pending_quiz）；伴学答疑从对话历史
读题卡答案判对错，判定/讲解口径沉淀在 tutor 的 SOP（``skills/tutor_sop.md``）。

- 出题：文本出现「判断题」→ judge=True 规格 → 题卡带 ``judge: true`` 与 answer 下发。
- 落库：``chat()`` 不剥离答案，题卡随 assistant 消息 payload 进历史；Conversation 再无
  pending_quiz 列。
- 判定：tutor 不再从 ``ctx.extra`` 读 pending_quiz（服务端注入已删），口径在 SOP 里。
"""
from __future__ import annotations

import asyncio
import json
import uuid
from types import SimpleNamespace

from sqlmodel import select

from agent_core.ports import StructuredDone, TextDelta
from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    assistant_message,
    data_event,
    done,
    run_started,
    tool_call,
    tool_result,
    user_message,
)
from agent_core.registry import discover_subagent_manifests
from agent_core.runtime import RouteDecision
from agent_core.subagent import SubAgentContext
from app.ai.subagents.question.agent import QuestionSubAgent, parse_specs_from_text
from app.ai.subagents.tutor.agent import TutorSubAgent
from app.db.models import Conversation, Message
from app.domain.provider import EducationLLMProvider
from app.features.assistant.schemas import AssistantChatReq, CoursewareContext
from app.features.assistant.service import chat

# 固定判断题面（只含题面四要素；subject/grade/judge 由 spec 回填）。
_JUDGE_QUESTION: dict = {
    "stem": "平行四边形是轴对称图形",
    "options": ["对", "错"],
    "answer": "错",
    "explanation": "平行四边形两组对边平行且相等，但不是轴对称图形。",
}

# 题卡（judge=True）：连答案一起下发 / 落库，前端按 judge 标记隐藏待揭示。
_JUDGE_CARD: dict = {
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


class _JudgeFakeProvider(EducationLLMProvider):
    """确定性出题替身：按 schema 调用返回固定判断题面。"""

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if schema is not None:
            yield TextDelta(delta="先确认考查点")
            yield StructuredDone(data=dict(_JUDGE_QUESTION))
            return
        yield TextDelta(delta="讲解")

    async def tutor(
        self, *, grade, subject, knowledge_point, context, question, history=None
    ):
        return "讲解"

    async def grade_open(self, *, question, student_answer) -> dict:
        return {}


class _TutorFakeProvider(EducationLLMProvider):
    """确定性伴学替身：记录讲解上下文与历史，隔离真实模型。"""

    def __init__(self) -> None:
        self.last_tutor_context: str | None = None
        self.last_tutor_history: list | None = None

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        yield TextDelta(delta="讲解")

    async def tutor(
        self, *, grade, subject, knowledge_point, context, question, history=None
    ):
        self.last_tutor_context = context
        self.last_tutor_history = history
        return "答错啦，先看看平行四边形沿哪条线对折能不能完全重合。"

    async def grade_open(self, *, question, student_answer) -> dict:
        return {}


async def _drive(agent, ctx) -> list:
    return [ev async for ev in agent.run(ctx.message, ctx)]


async def _drain_chat(chat_coro) -> list[str]:
    """``chat`` 是 async def 返回异步生成器：先 await 取生成器再迭代。"""
    gen = await chat_coro
    return [frame async for frame in gen]


def _parse_sse(frames: list[str]) -> list[dict]:
    """SSE 帧 ``data: {json}\\n\\n`` → dict 列表。"""
    out = []
    for f in frames:
        if f.startswith("data: "):
            out.append(json.loads(f[len("data: ") :].strip()))
    return out


def _msgs(db, conv_id) -> list[Message]:
    return list(
        db.exec(
            select(Message)
            .where(Message.conversation_id == conv_id)
            .order_by(Message.turn.asc())
        ).all()
    )


# ── 出题：判断题规格由出题子代理自主判定 ──────────────────────────────────────


def test_parse_specs_from_text_detects_judge():
    """文本出现「判断题」→ judge=True；普通选择题不带。"""
    judge_specs = parse_specs_from_text("帮我出1道三年级数学判断题，关于轴对称")
    assert len(judge_specs) == 1
    assert judge_specs[0]["judge"] is True
    assert judge_specs[0]["qtype"] == "choice"  # 判断题是 choice 的二选一特例
    assert judge_specs[0]["knowledge_point"] == "轴对称"

    plain = parse_specs_from_text("帮我出3道三年级数学选择题，关于分数")
    assert plain[0]["judge"] is False


def test_judge_spec_card_keeps_answer_and_flags_judge():
    """judge 规格 → 题卡带 ``judge: true`` 且**答案不剥离**（前端据此隐藏待揭示）。"""
    agent = QuestionSubAgent(provider=_JudgeFakeProvider(), retriever=None)
    ctx = SubAgentContext(
        role="teacher",
        message="",
        extra={
            "specs": [
                {
                    "subject": "数学",
                    "grade": 4,
                    "knowledge_point": "轴对称",
                    "qtype": "choice",
                    "difficulty": "easy",
                    "count": 1,
                    "judge": True,
                }
            ]
        },
    )
    events = asyncio.run(_drive(agent, ctx))
    data = [e for e in events if e.eventType == EVENT_DATA]
    assert len(data) == 1
    card = data[0].data["result"]
    assert card["judge"] is True
    assert card["answer"] == "错"
    # 选项是对象（ADR-0089）：text 恒存在（判题依据），figure_key 为图形身份键。
    assert [o["text"] for o in card["options"]] == ["对", "错"]
    assert card["explanation"]


# ── 落库：chat() 不剥离答案，题卡随历史进库 ──────────────────────────────────


class _JudgeCardRuntime:
    """桩 runtime：emit 一张含答案的判断题卡，模拟出题子代理的产出。"""

    def __init__(self) -> None:
        self.business = None
        self.extra = None

    async def decide(self, signal, *, role: str, deps) -> RouteDecision:
        return RouteDecision(business="question", name="出题助手")

    async def run(self, message, *, role, ctx, deps, business=None, session=None):
        self.business = business
        self.extra = ctx.extra
        yield run_started()
        yield user_message(message)
        yield tool_call("generate_question", label="出题")
        yield data_event(dict(_JUDGE_CARD), extra={"type": "question"})
        yield tool_result("generate_question", {"count": 1})
        yield assistant_message("请判断「对」或「错」后回答。")
        yield done(ctx.extra.get("session_id"))


def test_chat_keeps_judge_card_answer_in_history(db):
    """题卡连答案下发并落库（服务端不再有剥离 / pending_quiz 分支）。

    ADR-0095 预检：出题业务在缺 subject/grade 时会先澄清而非直接生成，故这里带课件
    上下文（subject=数学 / grade=4）使必填齐备、走「汇总确认 → 生成」路径，验证题卡
    仍连答案落库。
    """
    tid = uuid.uuid4()
    rt = _JudgeCardRuntime()
    caller = SimpleNamespace(
        role="teacher",
        user=SimpleNamespace(id=tid, teacher_id=tid, class_id=None),
    )
    req = AssistantChatReq(
        message="请为「轴对称」出一道判断题，等我回答。",
        courseware=CoursewareContext(subject="数学", grade=4),
    )

    frames = asyncio.run(
        _drain_chat(chat(caller=caller, req=req, session=db, runtime=rt))
    )
    parsed = _parse_sse(frames)

    # 题卡连答案下发：前端按 judge 标记隐藏待揭示。
    cards = [p["data"] for p in parsed if p["eventType"] == EVENT_DATA]
    assert len(cards) == 1
    assert cards[0]["type"] == "question"
    assert cards[0]["result"]["judge"] is True
    assert cards[0]["result"]["answer"] == "错"

    # 落库：题卡随 assistant 消息进历史（答案一并留存，tutor 从历史读它判定）。
    conv = db.exec(select(Conversation).where(Conversation.teacher_id == tid)).one()
    stored = [
        c["result"]
        for m in _msgs(db, conv.id)
        if m.payload and m.payload.get("cards")
        for c in m.payload["cards"]
        if isinstance(c, dict) and c.get("type") == "question"
    ]
    assert any(c.get("judge") is True and c["answer"] == "错" for c in stored)

    # 服务端再无待判定态列（ADR-0089 删列）。
    assert not hasattr(conv, "pending_quiz")


def test_chat_text_route_reaches_question_agent_without_action(db):
    """判断题不再靠 quiz_generate 动作键：纯文本即可经 decide 落到出题助手。

    ADR-0095 预检下带课件上下文（subject=数学 / grade=4）使必填齐备，run 仍被调用、
    定向仍为 question。
    """
    tid = uuid.uuid4()
    rt = _JudgeCardRuntime()
    caller = SimpleNamespace(
        role="teacher",
        user=SimpleNamespace(id=tid, teacher_id=tid, class_id=None),
    )
    req = AssistantChatReq(
        message="请为「轴对称」出一道判断题，等我回答。",
        courseware=CoursewareContext(subject="数学", grade=4),
    )

    asyncio.run(
        _drain_chat(chat(caller=caller, req=req, session=db, runtime=rt))
    )
    # 请求不带 action；定向由桩 decide 给出（真实路由由契约测试覆盖）。
    assert rt.business == "question"


# ── 判定：tutor 从历史读答案，服务端不再注入待判定态 ─────────────────────────


def test_tutor_judges_from_history_without_pending_quiz_injection():
    """tutor 不再从 ctx.extra 读 pending_quiz；历史（含题卡）照常交给模型。"""
    provider = _TutorFakeProvider()
    agent = TutorSubAgent(provider=provider, retriever=None)
    history = [
        {"role": "user", "content": "请为「轴对称」出一道判断题，等我回答。"},
        {"role": "assistant", "content": "平行四边形是轴对称图形（对 / 错）"},
    ]
    ctx = SubAgentContext(role="teacher", message="对", history=history)

    events = asyncio.run(_drive(agent, ctx))

    assert any(e.eventType == EVENT_ASSISTANT_MESSAGE for e in events)
    # 服务端注入已删（_quiz_hint_context / pending_quiz 均不存在）。
    assert provider.last_tutor_context is not None
    assert "【判断题待判定】" not in provider.last_tutor_context
    # 对话历史（含题卡）原样进模型上下文——答案随历史被 tutor 读到。
    assert provider.last_tutor_history == history


def test_tutor_sop_carries_judge_rubric():
    """判定/讲解口径沉淀在 tutor SOP（skills/tutor_sop.md），随 manifest 注入。"""
    manifests = discover_subagent_manifests()
    sop = manifests["tutor"].skill_prompt
    assert "判断题待判定" in sop
    # 求讲解 → 揭示答案；含糊 → 请他用对/错回答；答错 → 先给支架。
    assert "对" in sop and "错" in sop
    assert "支架" in sop


def test_tutor_manifest_declares_no_actions():
    """伴学答疑不再声明任何动作键：课件提示 / 判定均由上下文与历史驱动。"""
    manifests = discover_subagent_manifests()
    assert manifests["tutor"].actions == []
