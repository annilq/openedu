"""落库出题（Genkit 非流式路径）单测（ADR-0015 / 票据 08）。

验证 resolve_engine 解析到的真实引擎（如 ollama）被出题落库路径实际使用，
而非静默回退 mock；并验证安全闸门：真实模型产出不安全时返回 None 由调用方回退。
"""
from __future__ import annotations

import asyncio
from types import SimpleNamespace

import pytest

from app.ai.flows import QuestionSchema, generate_question
from app.domain.provider import GeneratedQuestion
from app.domain.safety import SafetyVerdict


def _fake_engine(model_str: str = "ollama/llama3"):
    """构造一个 genkit.generate 直接回吐固定 QuestionSchema 的假引擎。"""
    resp = SimpleNamespace(
        output=QuestionSchema(
            subject="数学",
            grade=2,
            knowledge_point="加法",
            qtype="calc",
            difficulty="easy",
            stem="1+1=?",
            options=None,
            answer="2",
            explanation="这是加法",
        )
    )

    async def _generate(*, model=None, system=None, prompt=None, output_schema=None):
        return resp

    return SimpleNamespace(
        genkit=SimpleNamespace(generate=_generate, model=model_str),
        model=model_str,
    )


def test_generate_question_returns_generated():
    engine = _fake_engine()
    g = asyncio.run(
        generate_question(
            engine,
            subject="数学",
            grade=2,
            knowledge_point="加法",
            qtype="calc",
            difficulty="easy",
        )
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
    """真实模型产出不安全 → 返回 None，由路由层回退 MockProvider。"""
    monkeypatch.setattr(
        "app.ai.flows.check_output", lambda text: SafetyVerdict(safe=False, reason="测试")
    )
    engine = _fake_engine()
    g = asyncio.run(
        generate_question(
            engine,
            subject="数学",
            grade=2,
            knowledge_point="加法",
            qtype="calc",
            difficulty="easy",
        )
    )
    assert g is None


def test_generate_question_passes_model_and_prompt(monkeypatch):
    """引擎的 genkit.generate 确实被以真实 model 调用（确保不是走 mock 分支）。"""
    captured = {}

    async def _generate(*, model=None, system=None, prompt=None, output_schema=None):
        captured["model"] = model
        captured["prompt"] = prompt
        captured["schema"] = output_schema
        return SimpleNamespace(
            output=QuestionSchema(subject="x", grade=1, knowledge_point="kp", qtype="fill", difficulty="medium", stem="x", options=None, answer="y", explanation="z")
        )

    engine = SimpleNamespace(
        genkit=SimpleNamespace(generate=_generate, model="ollama/llama3"),
        model="ollama/llama3",
    )
    asyncio.run(
        generate_question(
            engine,
            subject="语文",
            grade=3,
            knowledge_point="字词",
            qtype="fill",
            difficulty="medium",
            interests=["恐龙"],
        )
    )
    assert captured["model"] == "ollama/llama3"
    assert captured["schema"] is QuestionSchema
    assert "恐龙" in captured["prompt"]


@pytest.mark.parametrize("focus_interest,expect_focus", [("太空", True), (None, False)])
def test_generate_question_focus_clause(focus_interest, expect_focus):
    captured = {}

    async def _generate(*, model=None, system=None, prompt=None, output_schema=None):
        captured["prompt"] = prompt
        return SimpleNamespace(
            output=QuestionSchema(subject="x", grade=1, knowledge_point="kp", qtype="fill", difficulty="medium", stem="x", options=None, answer="y", explanation="z")
        )

    engine = SimpleNamespace(
        genkit=SimpleNamespace(generate=_generate, model="ollama/llama3"),
        model="ollama/llama3",
    )
    asyncio.run(
        generate_question(
            engine,
            subject="科学",
            grade=4,
            knowledge_point="行星",
            qtype="open",
            difficulty="hard",
            focus_interest=focus_interest,
        )
    )
    if expect_focus:
        assert "太空" in captured["prompt"]
    else:
        assert "太空" not in captured["prompt"]
