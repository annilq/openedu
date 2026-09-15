"""GenkitProvider 真实模型 smoke（迁移 08b / 纯单栈 Genkit）。

默认跳过。仅在本地已起真实模型服务 + 显式开启时运行：

    RUN_LLM_SMOKE=1 \\
    SMOKE_MODEL_NAME=llama3 \\
    SMOKE_MODEL_BASE_URL=http://localhost:11434 \\   # 缺省即此值（ollama）
    SMOKE_MODEL_API_KEY=ollama \\                    # 必填：ADR-0039 起新增模型强制带 key
    SMOKE_MODEL_PROVIDER=ollama \\                   # 缺省 ollama；OpenAI 兼容填 openai_compat
        uv run pytest tests/domain/test_llm_smoke.py -m smoke -v

ADR-0039 起模型只存在于 `ModelConfig` 表（内置目录已移除），因此本用例自建一行
ModelConfig，再走 ``resolve_engine`` → 真实生成，验证「配置解析 → 引擎 → 出题契约」
这条链路对真实模型成立（业务层零改动）。
"""
from __future__ import annotations

import asyncio
import os

import pytest
from sqlmodel import Session

from app.ai import generate_question, resolve_engine
from app.core.crypto import encrypt
from app.db.models import ModelConfig, User
from app.domain import build_provider
from app.domain.genkit_provider import GenkitProvider

_MODEL_NAME = os.environ.get("SMOKE_MODEL_NAME", "")
_PROVIDER = os.environ.get("SMOKE_MODEL_PROVIDER", "ollama")
_BASE_URL = os.environ.get("SMOKE_MODEL_BASE_URL") or "http://localhost:11434"
_API_KEY = os.environ.get("SMOKE_MODEL_API_KEY", "")

_smoke_enabled = os.environ.get("RUN_LLM_SMOKE") == "1" and bool(_MODEL_NAME) and bool(_API_KEY)

pytestmark = [
    pytest.mark.smoke,
    pytest.mark.skipif(
        not _smoke_enabled,
        reason="需 SMOKE_MODEL_NAME + SMOKE_MODEL_API_KEY 且 RUN_LLM_SMOKE=1",
    ),
]


def test_build_provider_is_genkit():
    assert isinstance(build_provider(), GenkitProvider)


def test_genkit_real_generate(db: Session):
    parent = User(
        username="smoke_parent@ex.com",
        display_name="smoke",
        role="parent",
        hashed_password="x",
        parent_id=None,
    )
    db.add(parent)
    db.commit()
    db.refresh(parent)

    mc = ModelConfig(
        parent_id=parent.id,
        label="smoke",
        provider=_PROVIDER,
        base_url=_BASE_URL,
        model_name=_MODEL_NAME,
        api_key_enc=encrypt(_API_KEY),
        is_default=True,
    )
    db.add(mc)
    db.commit()
    db.refresh(mc)

    engine = resolve_engine(str(mc.id), parent_id=str(parent.id), session=db)
    assert engine is not None, "未解析到引擎（ModelConfig 自建行应可解析）"
    provider = build_provider(engine=engine)
    q = asyncio.run(
        generate_question(
            provider,
            subject="数学",
            grade=2,
            knowledge_point="加法",
            qtype="calc",
            difficulty="easy",
        )
    )
    assert q is not None and q.subject and q.stem and q.answer
