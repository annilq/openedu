"""GenkitProvider 单测（迁移 08b：纯单栈）。

默认 LLM_PROVIDER=mock 下验证确定性 mock 分支（出题/答疑/批改），与 LLMProvider 契约一致；
真实模型路径由 gated smoke（test_llm_smoke.py）覆盖。
"""
from __future__ import annotations

import asyncio

from app.domain.genkit_provider import GenkitProvider
from app.domain.provider import GeneratedQuestion


def _provider() -> GenkitProvider:
    return GenkitProvider()


def test_mock_question_is_deterministic():
    p = _provider()
    q1 = asyncio.run(
        p.generate_question(subject="数学", grade=2, knowledge_point="加法", qtype="calc", difficulty="easy")
    )
    q2 = asyncio.run(
        p.generate_question(subject="数学", grade=2, knowledge_point="加法", qtype="calc", difficulty="easy")
    )
    assert isinstance(q1, GeneratedQuestion)
    assert q1.stem == q2.stem and q1.answer == q2.answer


def test_mock_question_open_has_explanation():
    p = _provider()
    q = asyncio.run(
        p.generate_question(subject="语文", grade=3, knowledge_point="拼音", qtype="open", difficulty="medium")
    )
    assert q.qtype == "open"
    assert q.explanation


def test_mock_tutor_text_contains_knowledge_point():
    p = _provider()
    text = asyncio.run(
        p.tutor(grade=2, subject="数学", knowledge_point="加法", context=None, question="1+1=?")
    )
    assert "加法" in text


class _FakeQuestion:
    """模拟 ORM Question（含 knowledge_point / explanation），供 mock 批改判定。"""

    knowledge_point = "加法"
    explanation = "根据加法定义"


def test_mock_grade_open_keyword_match():
    p = _provider()
    res = asyncio.run(p.grade_open(question=_FakeQuestion(), student_answer="加法是合并数量的方法"))
    assert res["correct"] is True
    assert res["score"] == 1.0


def test_mock_grade_open_wrong():
    p = _provider()
    res = asyncio.run(p.grade_open(question=_FakeQuestion(), student_answer=""))
    assert res["correct"] is False
    assert res["score"] == 0.0
