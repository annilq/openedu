"""模型解析单元测试（ADR-0015 / 票据 08）。

验证 ``resolve_engine`` 统一走「模型管理」配置后的解析优先级：
  1. 显式 ModelConfig id（家长自定义，需 parent_id + session，越权返回 None）
  2. 内置模型 id（settings.BUILTIN_MODELS 目录）
  3. 未指定 model_ref 时，回落本家长的默认 ModelConfig（模型管理「设为默认」）
  4. 均无 → 返回 None
"""
from __future__ import annotations

import json

from sqlmodel import Session

from app.ai import list_builtin_models, resolve_engine
from app.db.models import ModelConfig, User


def _make_parent(db: Session, idx: int) -> User:
    parent = User(
        username=f"p{idx}@ex.com",
        display_name=f"家长{idx}",
        role="parent",
        hashed_password="x",
        parent_id=None,
    )
    db.add(parent)
    db.commit()
    db.refresh(parent)
    return parent


def _make_default_model(
    db: Session, parent: User, model_name: str = "gpt-4o-mini"
) -> ModelConfig:
    mc = ModelConfig(
        parent_id=parent.id,
        provider="openai_compat",
        model_name=model_name,
        api_key_enc="dummy-enc",  # 解析只构造引擎，不发网络请求
        base_url=None,
        label=model_name,
        is_default=True,
    )
    db.add(mc)
    db.commit()
    db.refresh(mc)
    return mc


def test_resolve_none_without_default_returns_none(db: Session) -> None:
    """家长未配置任何默认模型时，未指定 model_ref → None（不再回退全局 LLM_PROVIDER）。"""
    parent = _make_parent(db, 11)
    assert resolve_engine(None, parent_id=str(parent.id), session=db) is None


def test_resolve_none_falls_back_to_parent_default(db: Session) -> None:
    """未指定 model_ref 时，回落本家长的默认 ModelConfig（模型管理）。"""
    parent = _make_parent(db, 12)
    _make_default_model(db, parent)
    engine = resolve_engine(None, parent_id=str(parent.id), session=db)
    assert engine is not None
    assert engine.model == "openai/gpt-4o-mini"


def test_resolve_explicit_unknown_ref_returns_none(db: Session) -> None:
    """显式引用不存在的 id 不回落默认模型，应返回 None（避免静默误用默认引擎）。"""
    parent = _make_parent(db, 13)
    _make_default_model(db, parent)
    assert resolve_engine("nonexistent-id", parent_id=str(parent.id), session=db) is None


def test_builtin_model_resolves_engine(monkeypatch) -> None:
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


def test_list_builtin_models_parses_json(monkeypatch) -> None:
    monkeypatch.setattr(
        "app.ai.engine.settings.BUILTIN_MODELS",
        json.dumps([{"id": "x", "label": "X", "provider": "openai_compat", "model_name": "gpt"}]),
    )
    builtin = list_builtin_models()
    assert builtin and builtin[0]["id"] == "x"
