"""模型管理（ADR-0015 / 票据 08）：仅家长可用。

GET  /models          列出可用模型（内置 + 本家长自定义，不含 api_key 明文）
POST /models          新增自定义模型（api_key 写入前加密）
GET  /models/default  查本家长默认模型
PUT  /models/default  设本家长默认模型（body: {id}）
GET  /models/{id}     查单个自定义模型（越权 / 不存在 → 404）
PUT  /models/{id}     改自定义模型
DELETE /models/{id}   删自定义模型

注意路由顺序：/default 必须排在 /{model_id} 之前，否则 /default 会被 /{model_id}
捕获（model_id="default" 不是合法 UUID → 422/405）。
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from app.ai.engine import list_builtin_models
from app.api.deps import CurrentParent, SessionDep
from app.core.errors import AppErrorException, ErrCode
from app.crud import (
    create_model_config,
    delete_model_config,
    get_default_model_config,
    get_model_config,
    list_model_configs,
    update_model_config,
)

router = APIRouter(prefix="/models", tags=["models"])


class ModelConfigCreate(BaseModel):
    label: str = Field(max_length=64)
    provider: str = Field(max_length=32)  # ollama | openai_compat
    base_url: str | None = Field(default=None, max_length=512)
    model_name: str = Field(max_length=128)
    api_key: str | None = None
    is_default: bool = False


class ModelConfigUpdate(BaseModel):
    label: str | None = Field(default=None, max_length=64)
    provider: str | None = Field(default=None, max_length=32)
    base_url: str | None = Field(default=None, max_length=512)
    model_name: str | None = Field(default=None, max_length=128)
    api_key: str | None = None
    is_default: bool | None = None


class ModelConfigResp(BaseModel):
    id: uuid.UUID
    label: str
    provider: str
    base_url: str | None
    model_name: str
    is_default: bool


class BuiltinModelInfo(BaseModel):
    id: str
    label: str
    provider: str
    model_name: str
    base_url: str | None = None


class ModelListResp(BaseModel):
    builtin: list[BuiltinModelInfo]
    custom: list[ModelConfigResp]


class DefaultModelReq(BaseModel):
    id: uuid.UUID


def _to_resp(mc) -> ModelConfigResp:  # type: ignore[no-untyped-def]
    return ModelConfigResp(
        id=mc.id,
        label=mc.label,
        provider=mc.provider,
        base_url=mc.base_url,
        model_name=mc.model_name,
        is_default=mc.is_default,
    )


@router.get("", response_model=ModelListResp)
def list_models(*, session: SessionDep, parent: CurrentParent) -> ModelListResp:
    builtin = [
        BuiltinModelInfo(
            id=m["id"],
            label=m.get("label", m["model_name"]),
            provider=m.get("provider", "openai_compat"),
            model_name=m["model_name"],
            base_url=m.get("base_url"),
        )
        for m in list_builtin_models()
    ]
    custom = [_to_resp(mc) for mc in list_model_configs(session=session, parent_id=parent.id)]
    return ModelListResp(builtin=builtin, custom=custom)


@router.post("", response_model=ModelConfigResp, status_code=status.HTTP_201_CREATED)
def create_model(*, session: SessionDep, parent: CurrentParent, payload: ModelConfigCreate) -> ModelConfigResp:
    if payload.provider not in ("ollama", "openai_compat"):
        raise AppErrorException(ErrCode.VALIDATION, "provider 仅支持 ollama / openai_compat")
    mc = create_model_config(
        session=session,
        parent_id=parent.id,
        label=payload.label,
        provider=payload.provider,
        base_url=payload.base_url,
        model_name=payload.model_name,
        api_key=payload.api_key,
        is_default=payload.is_default,
    )
    return _to_resp(mc)


@router.get("/default", response_model=ModelConfigResp)
def get_default(*, session: SessionDep, parent: CurrentParent) -> ModelConfigResp:
    mc = get_default_model_config(session=session, parent_id=parent.id)
    if mc is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="未设置默认模型")
    return _to_resp(mc)


@router.put("/default", response_model=ModelConfigResp)
def set_default(*, session: SessionDep, parent: CurrentParent, payload: DefaultModelReq) -> ModelConfigResp:
    mc = get_model_config(session=session, id=payload.id, parent_id=parent.id)
    if mc is None:
        raise AppErrorException(ErrCode.NOT_FOUND, "模型不存在或不属于你的账号")
    updated = update_model_config(
        session=session, id=payload.id, parent_id=parent.id, is_default=True
    )
    return _to_resp(updated)


@router.get("/{model_id}", response_model=ModelConfigResp)
def get_model(*, session: SessionDep, parent: CurrentParent, model_id: uuid.UUID) -> ModelConfigResp:
    mc = get_model_config(session=session, id=model_id, parent_id=parent.id)
    if mc is None:
        raise AppErrorException(ErrCode.NOT_FOUND, "模型不存在或不属于你的账号")
    return _to_resp(mc)


@router.put("/{model_id}", response_model=ModelConfigResp)
def update_model(
    *, session: SessionDep, parent: CurrentParent, model_id: uuid.UUID, payload: ModelConfigUpdate
) -> ModelConfigResp:
    fields = payload.model_dump(exclude_unset=True)
    if "provider" in fields and fields["provider"] not in ("ollama", "openai_compat"):
        raise AppErrorException(ErrCode.VALIDATION, "provider 仅支持 ollama / openai_compat")
    mc = update_model_config(session=session, id=model_id, parent_id=parent.id, **fields)
    if mc is None:
        raise AppErrorException(ErrCode.NOT_FOUND, "模型不存在或不属于你的账号")
    return _to_resp(mc)


@router.delete("/{model_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_model(*, session: SessionDep, parent: CurrentParent, model_id: uuid.UUID) -> None:
    ok = delete_model_config(session=session, id=model_id, parent_id=parent.id)
    if not ok:
        raise AppErrorException(ErrCode.NOT_FOUND, "模型不存在或不属于你的账号")
