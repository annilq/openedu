"""出题流式原语单测（ADR-0028：output_schema 约束 + 原生思维链）。

解析层只判定、不猜测，因此用例围绕「模型产出什么 → 得到什么事件」：
1. 原生思维链（ReasoningPart）→ 逐段 ReasoningDelta，题卡来自类型化 output；
2. 无原生思维链 → 推理取 output_schema 的 reasoning 字段（整块随卡到达）；
3. 模型无产出 / 题面不安全 → QuestionFailed（显式，不静默跳过）；
4. 推理不安全 → 只丢推理，题卡照发；
5. 解析器是同步 push 状态机，任意切分点结果一致。
"""
from __future__ import annotations

import asyncio
from types import SimpleNamespace

import pytest

from app.ai.generation import generate_question_stream
from app.ai.parsers.question import QuestionSpec, SchemaQuestionParser
from app.ai.segment import Segment, SegmentKind
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


def _out(**kw) -> SimpleNamespace:
    """模拟 output_schema 约束下的类型化产出。"""
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
    return SimpleNamespace(**base)


def _chunk(text: str | None = None, reasoning: str | None = None):
    """模拟 Genkit chunk：content=[Part(root=TextPart|ReasoningPart)]。"""
    root = SimpleNamespace(text=text, reasoning=reasoning)
    return SimpleNamespace(content=[SimpleNamespace(root=root)])


def _segments(text: str, size: int = 7):
    return [text[i : i + size] for i in range(0, len(text), size)]


def _fake_stream_engine(chunks, output=None, model: str = "openai/deepseek-v4-flash"):
    """构造 generate_stream 假引擎：按给定 chunk 逐段产出，结束时给出类型化 output。"""

    async def _stream():
        for c in chunks:
            yield c

    class _Resp:
        def __init__(self) -> None:
            self.stream = _stream()

            async def _done():
                return SimpleNamespace(output=output)

            # 对齐 genkit ModelStreamResponse：response 是 awaitable，不是方法
            self.response = _done()

    def _generate_stream(*, model=None, system=None, prompt=None, **kwargs):
        return _Resp()

    return SimpleNamespace(
        genkit=SimpleNamespace(generate_stream=_generate_stream, model=model),
        model=model,
    )


def _collect(engine):
    async def _run():
        return [ev async for ev in generate_question_stream(engine, **_SPEC)]

    return asyncio.run(_run())


def _reasoning_text(events) -> str:
    return "".join(e.delta for e in events if isinstance(e, ReasoningDelta))


def _cards(events):
    return [e for e in events if isinstance(e, QuestionCard)]


def _failures(events):
    return [e for e in events if isinstance(e, QuestionFailed)]


# ───────────────────────── 1) 原生思维链 ─────────────────────────
def test_native_reasoning_streams_deltas_then_card():
    chunks = [
        _chunk(reasoning="学生在通分上常错，"),
        _chunk(reasoning="先诱导分母相同。"),
        _chunk(text='{"stem": "1/2 + 1/2 = ?"}'),  # 约束 JSON，不参与解析
    ]
    engine = _fake_stream_engine(chunks, output=_out())
    events = _collect(engine)

    deltas = [e for e in events if isinstance(e, ReasoningDelta)]
    assert len(deltas) == 2, "原生思维链必须逐段下发，否则前端无从实时渲染"
    assert _reasoning_text(events) == "学生在通分上常错，先诱导分母相同。"

    cards = _cards(events)
    assert len(cards) == 1
    assert cards[0].question.stem == "1/2 + 1/2 = ?"
    assert cards[0].question.answer == "A"
    assert cards[0].question.subject == "数学"  # 由 spec 回填
    assert cards[0].reasoning == "学生在通分上常错，先诱导分母相同。"


# ───────────────────────── 2) 无原生思维链：取 schema 的 reasoning ─────────────────────────
def test_reasoning_falls_back_to_schema_field():
    engine = _fake_stream_engine(
        [_chunk(text='{"stem": "1/2 + 1/2 = ?"}')],
        output=_out(reasoning="考察同分母加法。"),
    )
    events = _collect(engine)

    assert _reasoning_text(events) == ""  # 无原生思维链 → 无增量
    cards = _cards(events)
    assert len(cards) == 1
    assert cards[0].reasoning == "考察同分母加法。"


# ───────────────────────── 3) 失败显式化 ─────────────────────────
def test_no_output_yields_question_failed():
    engine = _fake_stream_engine([_chunk(text="抱歉")], output=None)
    events = _collect(engine)
    assert _cards(events) == []
    assert [f.reason for f in _failures(events)] == ["模型未返回结构化题卡"]


def test_unsafe_stem_yields_question_failed(monkeypatch):
    monkeypatch.setattr(
        "app.ai.parsers.question.check_output",
        lambda text: SafetyVerdict(safe=("BAD" not in text), reason="测试"),
    )
    engine = _fake_stream_engine([_chunk(text="{}")], output=_out(stem="BAD 题面"))
    events = _collect(engine)

    assert _cards(events) == []
    assert [f.reason for f in _failures(events)] == ["生成内容未通过安全校验"]


def test_unsafe_reasoning_dropped_but_card_kept(monkeypatch):
    """推理单独过闸门：不安全只丢推理，好题不该被推理措辞连坐。"""
    monkeypatch.setattr(
        "app.ai.parsers.question.check_output",
        lambda text: SafetyVerdict(safe=("BAD" not in text), reason="测试"),
    )
    engine = _fake_stream_engine(
        [_chunk(text="{}")], output=_out(reasoning="BAD 推理")
    )
    events = _collect(engine)

    cards = _cards(events)
    assert len(cards) == 1
    assert cards[0].reasoning == ""


# ───────────────────────── 4) 解析器是同步 push 状态机 ─────────────────────────
@pytest.mark.parametrize("chunk_size", [1, 3, 17, 1000])
def test_reasoning_deltas_robust_to_any_chunk_boundary(chunk_size):
    """任意切分点都要得到同样的推理文本（不能因截断而丢内容）。"""
    text = "同分母相加，分子相加分母不变。"
    chunks = [_chunk(reasoning=s) for s in _segments(text, chunk_size)]
    engine = _fake_stream_engine(chunks, output=_out())
    events = _collect(engine)
    assert _reasoning_text(events) == text


def test_parser_is_synchronous_push_machine():
    """解析器无 async、无引擎依赖：直接喂 Segment 即可判定。"""
    parser = SchemaQuestionParser(spec=_QUESTION_NS)
    assert parser.feed(Segment(SegmentKind.TEXT, '{"stem": "x"}')) == []
    evs = parser.feed(Segment(SegmentKind.REASONING, "先想清楚。"))
    assert [type(e).__name__ for e in evs] == ["ReasoningDelta"]

    out = parser.finish(_out(stem="1/2 + 1/2 = ?"))
    assert len(out) == 1
    assert isinstance(out[0], QuestionCard)
    assert out[0].reasoning == "先想清楚。"
