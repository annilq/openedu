"""模型解析单元测试（ADR-0015 / 票据 08）。"""
from __future__ import annotations

import json

from app.ai import list_builtin_models, resolve_engine


def test_mock_provider_resolves_to_none(monkeypatch):
    # 默认配置 LLM_PROVIDER=mock → 无真实引擎，端点回退 MockProvider
    monkeypatch.setattr("app.ai.engine.settings.LLM_PROVIDER", "mock")
    assert resolve_engine(None) is None


def test_builtin_model_resolves_engine(monkeypatch):
    monkeypatch.setattr(
        "app.ai.engine.settings.BUILTIN_MODELS",
        json.dumps(
            [
                {
                    "id": "local-llama",
                    "label": "本地 Llama",
                    "provider": "ollama",
                    "model_name": "llama3",
                    "base_url": "http://localhost:11434",
                }
            ]
        ),
    )
    res = resolve_engine("local-llama")
    assert res is not None
    assert res.model == "ollama/llama3"
    assert res.genkit is not None


def test_list_builtin_models_parses_json(monkeypatch):
    monkeypatch.setattr(
        "app.ai.engine.settings.BUILTIN_MODELS",
        json.dumps([{"id": "x", "label": "X", "provider": "openai_compat", "model_name": "gpt"}]),
    )
    builtin = list_builtin_models()
    assert builtin and builtin[0]["id"] == "x"


def test_unknown_ref_falls_back_to_provider(monkeypatch):
    # 未知 id 且全局为 langchain 但缺配置 → None
    monkeypatch.setattr("app.ai.engine.settings.LLM_PROVIDER", "langchain")
    monkeypatch.setattr("app.ai.engine.settings.LLM_BASE_URL", "")
    monkeypatch.setattr("app.ai.engine.settings.LLM_MODEL", "")
    assert resolve_engine("nonexistent-id") is None
