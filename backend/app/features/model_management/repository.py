"""Repository layer for the model management feature (ADR-0015 / 票据 08)."""

import uuid

from sqlmodel import Session, select, update

from app.core.crypto import encrypt
from app.db.models import ModelConfig


def list_model_configs(*, session: Session, parent_id: uuid.UUID) -> list[ModelConfig]:
    """家长自定义模型列表（不含 api_key 明文）。"""
    return list(
        session.exec(select(ModelConfig).where(ModelConfig.parent_id == parent_id)).all()
    )


def get_model_config(
    *, session: Session, id: uuid.UUID, parent_id: uuid.UUID
) -> ModelConfig | None:
    """按 id 取自定义模型；越权（非本家长）返回 None。"""
    mc = session.get(ModelConfig, id)
    if mc is None or mc.parent_id != parent_id:
        return None
    return mc


def create_model_config(
    *,
    session: Session,
    parent_id: uuid.UUID,
    label: str,
    provider: str,
    base_url: str | None,
    model_name: str,
    api_key: str | None,
    is_default: bool = False,
) -> ModelConfig:
    if is_default:
        session.execute(
            update(ModelConfig)
            .where(ModelConfig.parent_id == parent_id)
            .values(is_default=False)
        )
    mc = ModelConfig(
        parent_id=parent_id,
        label=label,
        provider=provider,
        base_url=base_url,
        model_name=model_name,
        api_key_enc=encrypt(api_key),
        is_default=is_default,
    )
    session.add(mc)
    session.commit()
    session.refresh(mc)
    return mc


def update_model_config(
    *, session: Session, id: uuid.UUID, parent_id: uuid.UUID, **fields: object
) -> ModelConfig | None:
    mc = get_model_config(session=session, id=id, parent_id=parent_id)
    if mc is None:
        return None
    api_key = fields.pop("api_key", None)
    if api_key is not None:
        mc.api_key_enc = encrypt(api_key)
    if fields.get("is_default"):
        session.execute(
            update(ModelConfig)
            .where(ModelConfig.parent_id == parent_id, ModelConfig.id != id)
            .values(is_default=False)
        )
    for key, value in fields.items():
        if value is not None:
            setattr(mc, key, value)
    session.add(mc)
    session.commit()
    session.refresh(mc)
    return mc


def delete_model_config(*, session: Session, id: uuid.UUID, parent_id: uuid.UUID) -> bool:
    mc = get_model_config(session=session, id=id, parent_id=parent_id)
    if mc is None:
        return False
    session.delete(mc)
    session.commit()
    return True


def get_default_model_config(
    *, session: Session, parent_id: uuid.UUID
) -> ModelConfig | None:
    return session.exec(
        select(ModelConfig).where(
            ModelConfig.parent_id == parent_id, ModelConfig.is_default.is_(True)
        )
    ).first()
