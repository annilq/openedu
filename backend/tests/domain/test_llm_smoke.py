"""GenkitProvider 真实模型 smoke（迁移 08b / 纯单栈 Genkit）。

默认跳过。仅在本地已起 Ollama + RUN_LLM_SMOKE=1 时运行：

    BUILTIN_MODELS='[{"id":"local-llama","provider":"ollama",
      "base_url":"http://localhost:11434","model_name":"qwen2.5:latest"}]' \\
    RUN_LLM_SMOKE=1 \\
        uv run pytest tests/domain/test_llm_smoke.py -m smoke -v

验证：build_provider() 返回 GenkitProvider；若可解析真实引擎，经 flow 非流式入口出题
符合 GeneratedQuestion 契约（业务层零改动）。
"""
from __future__ import annotations

import asyncio
import json
import os

import pytest

from app.ai import generate_question, resolve_engine
from app.core.config import settings
from app.domain import build_provider
from app.domain.genkit_provider import GenkitProvider

try:
    _models = json.loads(settings.BUILTIN_MODELS) if settings.BUILTIN_MODELS else []
except (json.JSONDecodeError, TypeError):
    _models = []
_ollama_models = [m for m in _models if m.get("provider") == "ollama"]

_smoke_enabled = bool(_ollama_models) and os.environ.get("RUN_LLM_SMOKE") == "1"

pytestmark = [
    pytest.mark.smoke,
    pytest.mark.skipif(
        not _smoke_enabled,
        reason="需 BUILTIN_MODELS 含 provider=ollama 的模型，并设 RUN_LLM_SMOKE=1",
    ),
]


def test_build_provider_is_genkit():
    assert isinstance(build_provider(), GenkitProvider)


def test_genkit_real_generate(client):
    model = _ollama_models[0]
    engine = resolve_engine(model["id"])
    assert engine is not None, "未解析到 ollama 引擎"
    q = asyncio.run(
        generate_question(
            engine, subject="数学", grade=2, knowledge_point="加法", qtype="calc", difficulty="easy"
        )
    )
    assert q is not None and q.subject and q.stem and q.answer
