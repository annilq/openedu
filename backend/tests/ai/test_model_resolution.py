"""模型解析单元测试（ADR-0015 / ADR-0039）。

验证 ``resolve_engine`` 唯一走「模型管理」配置后的解析优先级：
  1. 显式 ModelConfig id（家长自建，需 parent_id + session，越权返回 None）
  2. 未指定 model_ref 时，回落本家长的默认 ModelConfig（模型管理「设为默认」）
  3. 显式引用但查不到 → None（不回落默认，避免静默用错引擎）

ADR-0039 起**不再有内置模型目录**，故原「内置 id 解析」两例已删除；
如有人重新引入第二份模型声明源，这里应有对应用例回来。
"""
from __future__ import annotations

from sqlmodel import Session

from app.ai import resolve_engine
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


def test_resolve_explicit_id_without_session_returns_none(db: Session) -> None:
    """显式引用但没带 session / parent_id → 无从鉴权，返回 None（不猜）。"""
    parent = _make_parent(db, 14)
    mc = _make_default_model(db, parent)
    assert resolve_engine(str(mc.id)) is None


def test_resolve_explicit_id_of_other_parent_returns_none(db: Session) -> None:
    """显式引用别人的 ModelConfig → None（越权不解析，且不回落自己的默认）。"""
    owner = _make_parent(db, 15)
    other = _make_parent(db, 16)
    mc = _make_default_model(db, owner)
    _make_default_model(db, other)  # 让对方也有默认模型，确保 None 不是「没得回落」造成的
    assert resolve_engine(str(mc.id), parent_id=str(other.id), session=db) is None
