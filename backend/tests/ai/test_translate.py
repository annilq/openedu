"""Translate 层单测：语义事件 → AG-UI 帧（含思维链攒批）。"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass

import pytest

from app.ai.runtime.protocol import EVENT_DATA, EVENT_STEP, EVENT_THINKING
from app.ai.runtime.translate import to_frames, translate_stream
from app.domain.provider import (
    GeneratedQuestion,
    QuestionCard,
    QuestionFailed,
    ReasoningDelta,
)


@dataclass(frozen=True)
class _Unknown:
    pass


def _card():
    return QuestionCard(
        question=GeneratedQuestion(
            subject="数学",
            grade=3,
            knowledge_point="分数",
            qtype="choice",
            stem="1/2 + 1/2 = ?",
            options=None,
            answer="A",
            explanation="同分母相加",
            difficulty="medium",
        ),
        reasoning="思路",
    )


def _frames(events):
    async def _src():
        for e in events:
            yield e

    async def _go():
        return [f async for f in translate_stream(_src())]

    return asyncio.run(_go())


def test_thinking_deltas_are_coalesced():
    """20 个 1 字增量必须被攒批，而不是 20 个 SSE 帧。"""
    deltas = [ReasoningDelta(delta=str(i % 10)) for i in range(20)]
    frames = _frames(deltas)

    assert all(f.eventType == EVENT_THINKING for f in frames)
    assert len(frames) < 5, f"攒批失效，仍发出 {len(frames)} 帧"
    assert "".join(f.text or "" for f in frames) == "".join(d.delta for d in deltas)


def test_pending_thinking_flushed_before_other_frame():
    """遇非 THINKING 帧必须先冲刷积压的推理，保证到达顺序不乱。"""
    frames = _frames([ReasoningDelta(delta="先想清楚。"), _card()])
    types = [f.eventType for f in frames]
    assert types == [EVENT_THINKING, EVENT_DATA]
    assert frames[0].text == "先想清楚。"
    assert frames[1].data["result"]["reasoning"] == "思路"


def test_failed_event_becomes_error_step():
    frames = _frames([QuestionFailed(reason="模型未返回结构化题卡")])
    assert [(f.eventType, f.status, f.label) for f in frames] == [
        (EVENT_STEP, "error", "模型未返回结构化题卡")
    ]


def test_unknown_event_raises():
    """未知语义事件必须炸，不能静默丢弃。"""
    with pytest.raises(TypeError, match="未注册的语义事件"):
        list(to_frames(_Unknown()))
