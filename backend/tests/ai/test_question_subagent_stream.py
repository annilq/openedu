"""出题 SubAgent 事件流单测：验证 STEP / THINKING / DATA 帧确实被产出。

回归背景：此前 ``QuestionSubAgent.run`` 每题一次性调用 ``generate_question``，
整条流只有 TOOL_CALL / DATA / TOOL_RESULT / ASSISTANT_MESSAGE，前端无从实时渲染
（``liveReasoning`` 恒空、``liveIndex`` 恒 -1 → 内联推理区永不显示）。

ADR-0028：语义事件经 ``translate_stream`` 转帧，**推理增量会按字符攒批**，
因此 THINKING 帧数少于语义事件数（同一次出题从数百帧降到数十帧）。
"""
from __future__ import annotations

import asyncio

from app.ai.runtime.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_STEP,
    EVENT_THINKING,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
)
from app.ai.subagents.base import SubAgentContext
from app.ai.subagents.question.agent import QuestionSubAgent
from app.domain.provider import (
    GeneratedQuestion,
    LLMProvider,
    QuestionCard,
    QuestionFailed,
    QuestionStreamEvent,
    ReasoningDelta,
)


def _card(subject: str, grade: int, kp: str, qtype: str, difficulty: str):
    return QuestionCard(
        question=GeneratedQuestion(
            subject=subject,
            grade=grade,
            knowledge_point=kp,
            qtype=qtype,
            stem="1/2 + 1/2 = ?",
            options=["1", "2", "3", "4"],
            answer="A",
            explanation="同分母相加",
            difficulty=difficulty,
        ),
        reasoning="先确认分母相同，再让分子相加。",
    )


class _FakeProvider(LLMProvider):
    """按「每次出题产出的事件序列」构造的假 provider。"""

    def __init__(self, events: list[QuestionStreamEvent]) -> None:
        self._events = events

    async def generate_question(self, **kwargs) -> GeneratedQuestion:
        return None

    async def grade_open(self, *, question, student_answer) -> dict:
        return {}

    async def tutor(self, **kwargs) -> str:
        return ""

    async def generate_question_stream(self, **kwargs):
        for ev in self._events:
            if isinstance(ev, QuestionCard):
                yield _card(
                    kwargs["subject"],
                    kwargs["grade"],
                    kwargs["knowledge_point"],
                    kwargs["qtype"],
                    kwargs["difficulty"],
                )
                continue
            yield ev


def _run(message: str, events: list[QuestionStreamEvent]):
    agent = QuestionSubAgent(
        provider=_FakeProvider(events), retriever=None, engine=None
    )
    ctx = SubAgentContext(role="parent", question=message)

    async def _go():
        return [ev async for ev in agent.run(message, ctx)]

    return asyncio.run(_go())


_OK = [
    ReasoningDelta(delta="先确认分母相同，"),
    ReasoningDelta(delta="再让分子相加。"),
    QuestionCard.__new__(QuestionCard),  # 占位，由 provider 换成真实题卡
]


def test_emits_step_thinking_and_data_per_question():
    events = _run("帮我出2道三年级数学选择题，关于分数", _OK)

    types = [e.eventType for e in events]
    assert EVENT_TOOL_CALL in types
    # 每题一个进度锚点：2 题 → 2 个 STEP
    assert types.count(EVENT_STEP) == 2
    # 每题 2 个推理增量，攒批（15 字 < 阈值）后合并为 1 帧 → 共 2 个 THINKING
    assert types.count(EVENT_THINKING) == 2
    assert types.count(EVENT_DATA) == 2
    assert EVENT_TOOL_RESULT in types
    assert EVENT_ASSISTANT_MESSAGE in types

    # 顺序：STEP 必须早于该题的 THINKING / DATA（前端据此展开内联区）
    assert types.index(EVENT_STEP) < types.index(EVENT_THINKING)
    assert types.index(EVENT_THINKING) < types.index(EVENT_DATA)


def test_thinking_frames_carry_no_business_extra():
    """推理帧不得带 extra.business，否则会被前端当作路由帧过滤掉。"""
    events = _run("帮我出1道三年级数学选择题", _OK)
    thinkings = [e for e in events if e.eventType == EVENT_THINKING]
    assert thinkings
    for ev in thinkings:
        assert not (ev.extra or {}).get("business")


def test_data_payload_carries_reasoning():
    events = _run("帮我出1道三年级数学选择题", _OK)
    data = [e for e in events if e.eventType == EVENT_DATA][0]
    assert data.data["type"] == "question"
    assert data.data["result"]["reasoning"] == "先确认分母相同，再让分子相加。"
    assert data.data["result"]["stem"] == "1/2 + 1/2 = ?"


def test_step_label_readable():
    events = _run("帮我出1道三年级数学选择题，关于分数", _OK)
    step = [e for e in events if e.eventType == EVENT_STEP][0]
    assert "数学" in (step.label or "")
    assert step.status == "running"


def test_failed_question_emits_error_step():
    """解析/闸门失败必须显式成 status=error 的 STEP，不得静默跳过。"""
    events = _run(
        "帮我出1道三年级数学选择题",
        [QuestionFailed(reason="模型未返回结构化题卡")],
    )
    steps = [e for e in events if e.eventType == EVENT_STEP]
    error_steps = [s for s in steps if s.status == "error"]
    assert [s.label for s in error_steps] == ["模型未返回结构化题卡"]
    assert [e.eventType for e in events].count(EVENT_DATA) == 0
