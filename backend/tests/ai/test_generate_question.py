"""落库出题（provider 非流式路径）单测（ADR-0032：统一走 LLMProvider）。

验证出题管线只依赖 ``LLMProvider``（不再直连 genkit 引擎），并验证安全闸门：
真实产出不安全时返回 None 由调用方以 LLM_UNAVAILABLE 报错（不静默回退假数据）。
"""
from __future__ import annotations

import asyncio

import pytest

from agent_core.ports import LLMProvider, StructuredDone
from app.ai.subagents.question.parsers import QuestionSchema
from app.ai.subagents.question.pipeline import generate_question
from app.domain.provider import GeneratedQuestion
from app.domain.safety import SafetyVerdict

# 模拟 output_schema 约束下的解析产出（subject/grade 等由 spec 回填）。
_Q_DICT = {
    "subject": "数学",
    "grade": 2,
    "knowledge_point": "加法",
    "qtype": "calc",
    "difficulty": "easy",
    "stem": "1+1=?",
    "options": None,
    "answer": "2",
    "explanation": "这是加法",
}


class _FakeProvider(LLMProvider):
    """回吐一帧 ``StructuredDone``；顺带记录收到的 system / prompt / schema。"""

    def __init__(self, data=None, *, captured: dict | None = None) -> None:
        self._data = data
        self._captured = captured if captured is not None else {}

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        self._captured["system"] = system
        self._captured["prompt"] = prompt
        self._captured["schema"] = schema
        yield StructuredDone(data=self._data)


def _run(provider, **kw):
    return asyncio.run(generate_question(provider, **kw))


def test_generate_question_returns_generated():
    g = _run(
        _FakeProvider(dict(_Q_DICT)),
        subject="数学", grade=2, knowledge_point="加法", qtype="calc", difficulty="easy",
    )
    assert isinstance(g, GeneratedQuestion)
    # 元信息由调用方按规格回填（模型只回吐 stem/options/answer/explanation）。
    assert g.subject == "数学"
    assert g.grade == 2
    assert g.knowledge_point == "加法"
    assert g.qtype == "calc"
    assert g.stem == "1+1=?"
    assert g.answer == "2"
    assert g.difficulty == "easy"


def test_generate_question_unsafe_returns_none(monkeypatch):
    """真实产出不安全 → 返回 None，由路由层以 LLM_UNAVAILABLE 报错。"""
    monkeypatch.setattr(
        "app.ai.subagents.question.parsers.check_output",
        lambda text: SafetyVerdict(safe=False, reason="测试"),
    )
    g = _run(
        _FakeProvider(dict(_Q_DICT)),
        subject="数学", grade=2, knowledge_point="加法", qtype="calc", difficulty="easy",
    )
    assert g is None


def test_generate_question_passes_prompt_and_schema():
    """provider 确实被以出题 schema 与含兴趣的 prompt 调用（确保不是空跑）。"""
    captured: dict = {}
    _run(
        _FakeProvider(dict(_Q_DICT), captured=captured),
        subject="语文", grade=3, knowledge_point="字词", qtype="fill", difficulty="medium",
        interests=["恐龙"],
    )
    assert captured["schema"] is QuestionSchema
    assert "恐龙" in captured["prompt"]
    assert "语文" in captured["prompt"]


@pytest.mark.parametrize("focus_interest,expect_focus", [("太空", True), (None, False)])
def test_generate_question_focus_clause(focus_interest, expect_focus):
    captured: dict = {}
    _run(
        _FakeProvider(dict(_Q_DICT), captured=captured),
        subject="科学", grade=4, knowledge_point="行星", qtype="open", difficulty="hard",
        focus_interest=focus_interest,
    )
    if expect_focus:
        assert "太空" in captured["prompt"]
    else:
        assert "太空" not in captured["prompt"]
