"""出题流式管线单测（ADR-0028 / ADR-0032：provider 流 → 语义事件）。

解析层只判定、不猜测，因此用例围绕「provider 产出什么 → 得到什么事件」：
1. 推理增量（TextDelta）→ 逐段 ReasoningDelta，题卡来自末帧 StructuredDone；
2. 无推理增量 → 推理取结构化产出的 reasoning 字段（整块随卡到达）；
3. 无结构化产出 / 题面不安全 → QuestionFailed（显式，不静默跳过）；
4. 推理不安全 → 只丢推理，题卡照发；
5. 推理增量在任意切分点拼接一致；
6. 解析器是同步 push 状态机，任意切分点结果一致。
"""
from __future__ import annotations

import asyncio

import pytest

from agent_core.adapters.genkit import Segment, SegmentKind
from agent_core.ports import LLMProvider, StructuredDone, TextDelta
from app.ai.subagents.question.parsers import QuestionSpec, SchemaQuestionParser
from app.ai.subagents.question.pipeline import build_question_prompts, stream_question
from app.domain.provider import (
    QuestionCard,
    QuestionFailed,
    ReasoningDelta,
)
from app.domain.safety import SafetyVerdict

_SPEC = dict(
    subject="数学",
    grade=3,
    knowledge_point="分数",
    qtype="choice",
    difficulty="medium",
)

_QUESTION_NS = QuestionSpec(
    subject="数学", grade=3, knowledge_point="分数", qtype="choice", difficulty="medium"
)


def _q_dict(**kw) -> dict:
    """模拟 output_schema 约束下的解析产出。"""
    base = dict(
        subject="数学",
        grade=3,
        knowledge_point="分数",
        qtype="choice",
        stem="1/2 + 1/2 = ?",
        options=["1", "2", "3", "4"],
        answer="A",
        explanation="同分母相加",
        difficulty="medium",
        reasoning="",
    )
    base.update(kw)
    return base


class _FakeProvider(LLMProvider):
    """按给定事件序列产出的假 provider。"""

    def __init__(self, events) -> None:
        self._events = events

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        for ev in self._events:
            yield ev


def _collect(provider):
    system_prompt, user_prompt, spec = build_question_prompts(**_SPEC)

    async def _run():
        return [
            ev
            async for ev in stream_question(
                provider, system_prompt=system_prompt, user_prompt=user_prompt, spec=spec
            )
        ]

    return asyncio.run(_run())


def _reasoning_text(events) -> str:
    return "".join(e.delta for e in events if isinstance(e, ReasoningDelta))


def _cards(events):
    return [e for e in events if isinstance(e, QuestionCard)]


def _failures(events):
    return [e for e in events if isinstance(e, QuestionFailed)]


# ───────────────────────── 1) 推理增量逐段下发 + 题卡 ─────────────────────────
def test_reasoning_deltas_then_card():
    provider = _FakeProvider(
        [
            TextDelta("学生在通分上常错，"),
            TextDelta("先诱导分母相同。"),
            StructuredDone(data=_q_dict()),
        ]
    )
    events = _collect(provider)

    deltas = [e for e in events if isinstance(e, ReasoningDelta)]
    assert len(deltas) == 2, "推理必须逐段下发，否则前端无从实时渲染"
    assert _reasoning_text(events) == "学生在通分上常错，先诱导分母相同。"

    cards = _cards(events)
    assert len(cards) == 1
    assert cards[0].question.stem == "1/2 + 1/2 = ?"
    assert cards[0].question.answer == "A"
    assert cards[0].question.subject == "数学"  # 由 spec 回填
    assert cards[0].reasoning == "学生在通分上常错，先诱导分母相同。"


# ───────────────────────── 2) 无推理增量：取结构化产出的 reasoning ─────────────────────────
def test_reasoning_falls_back_to_schema_field():
    provider = _FakeProvider([StructuredDone(data=_q_dict(reasoning="考察同分母加法。"))])
    events = _collect(provider)

    assert _reasoning_text(events) == ""  # 无推理增量 → 无 ReasoningDelta
    cards = _cards(events)
    assert len(cards) == 1
    assert cards[0].reasoning == "考察同分母加法。"


# ───────────────────────── 3) 失败显式化 ─────────────────────────
def test_no_structured_done_yields_question_failed():
    provider = _FakeProvider([TextDelta("抱歉")])
    events = _collect(provider)
    assert _cards(events) == []
    assert [f.reason for f in _failures(events)] == ["模型未返回结构化题卡"]


def test_unsafe_stem_yields_question_failed(monkeypatch):
    monkeypatch.setattr(
        "app.ai.subagents.question.parsers.check_output",
        lambda text: SafetyVerdict(safe=("BAD" not in text), reason="测试"),
    )
    provider = _FakeProvider([StructuredDone(data=_q_dict(stem="BAD 题面"))])
    events = _collect(provider)

    assert _cards(events) == []
    assert [f.reason for f in _failures(events)] == ["生成内容未通过安全校验"]


def test_unsafe_reasoning_dropped_but_card_kept(monkeypatch):
    """推理单独过闸门：不安全只丢推理，好题不该被推理措辞连坐。"""
    monkeypatch.setattr(
        "app.ai.subagents.question.parsers.check_output",
        lambda text: SafetyVerdict(safe=("BAD" not in text), reason="测试"),
    )
    provider = _FakeProvider([StructuredDone(data=_q_dict(reasoning="BAD 推理"))])
    events = _collect(provider)

    cards = _cards(events)
    assert len(cards) == 1
    assert cards[0].reasoning == ""


# ───────────────────────── 4) 推理增量在任意切分点拼接一致 ─────────────────────────
@pytest.mark.parametrize("chunk_size", [1, 3, 17, 1000])
def test_reasoning_deltas_robust_to_any_chunk_boundary(chunk_size):
    """任意切分点都要得到同样的推理文本（不能因截断而丢内容）。"""
    text = "同分母相加，分子相加分母不变。"
    chunks = [text[i : i + chunk_size] for i in range(0, len(text), chunk_size)]
    provider = _FakeProvider([TextDelta(c) for c in chunks] + [StructuredDone(data=_q_dict())])
    events = _collect(provider)
    assert _reasoning_text(events) == text


# ───────────────────────── 5) 解析器是同步 push 状态机 ─────────────────────────
def test_parser_is_synchronous_push_machine():
    """解析器无 async、无引擎依赖：直接喂 Segment 即可判定。"""
    parser = SchemaQuestionParser(spec=_QUESTION_NS)
    assert parser.feed(Segment(SegmentKind.TEXT, '{"stem": "x"}')) == []
    evs = parser.feed(Segment(SegmentKind.REASONING, "先想清楚。"))
    assert [type(e).__name__ for e in evs] == ["ReasoningDelta"]

    out = parser.finish(_q_dict(stem="1/2 + 1/2 = ?"))
    assert len(out) == 1
    assert isinstance(out[0], QuestionCard)
    assert out[0].reasoning == "先想清楚。"
