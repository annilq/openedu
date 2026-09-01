"""resolve_engine 回归：ModelConfig 自定义模型解析（流式 flow 静默回退 mock 的根因）。

历史 bug：流式 flow 把 parent_id 作为字符串（ctx.context 经 JSON 序列化）传入，
而 resolve_engine 第 1 步用 `mc.parent_id == parent_id`（UUID == str）比较，恒为
False，导致 ModelConfig 永不命中 → 回退全局 LLM_PROVIDER=mock，预览出题返回 mock。
同步 batch-generate 传的是 UUID 对象，故曾行为不一致。

本测试用「字符串 parent_id」模拟流式路径，确认：
1) 同家长的 ModelConfig 能解析出真实引擎；
2) 异家长（越权）返回 None；
3) 归一化比较对 UUID / str 都生效（engine.py 已改 `str(mc.parent_id) == str(parent_id)`）。
"""
from sqlmodel import Session

from app.ai.engine import resolve_engine
from app.models import ModelConfig, User


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


def _make_model(db: Session, parent: User, model_name: str = "gpt-4o-mini") -> ModelConfig:
    mc = ModelConfig(
        parent_id=parent.id,
        provider="openai_compat",
        model_name=model_name,
        api_key_enc="dummy-enc",  # 解析只构造引擎，不发网络请求
        base_url=None,
        label=model_name,
    )
    db.add(mc)
    db.commit()
    db.refresh(mc)
    return mc


def test_resolve_modelconfig_with_string_parent_id(db: Session) -> None:
    """流式路径：parent_id 为字符串时，应解析出真实引擎（回归 UUID==str 误判）。"""
    parent = _make_parent(db, 1)
    mc = _make_model(db, parent)

    engine = resolve_engine(str(mc.id), parent_id=str(parent.id), session=db)
    assert engine is not None
    # openai_compat 前缀 + 模型名
    assert engine.model == "openai/gpt-4o-mini"


def test_resolve_modelconfig_rejects_other_parent(db: Session) -> None:
    """越权：ModelConfig 归属其他家长时，解析应返回 None。"""
    owner = _make_parent(db, 2)
    intruder = _make_parent(db, 3)
    mc = _make_model(db, owner)

    engine = resolve_engine(str(mc.id), parent_id=str(intruder.id), session=db)
    assert engine is None


def test_resolve_modelconfig_requires_session(db: Session) -> None:
    """缺 session 时 ModelConfig 分支必须跳过（否则会误查/崩溃），回退 None。"""
    parent = _make_parent(db, 4)
    mc = _make_model(db, parent)

    engine = resolve_engine(str(mc.id), parent_id=str(parent.id))  # 无 session
    assert engine is None
