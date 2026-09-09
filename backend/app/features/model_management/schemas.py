"""Pydantic schemas for the model management feature."""

import uuid

from pydantic import BaseModel, Field

from app.db.models import ModelConfig


class ModelConfigCreate(BaseModel):
    label: str = Field(max_length=64)
    # provider 选填：仅填 provider_preset 时可自动按目录补全；二者至少其一。
    provider: str | None = Field(default=None, max_length=32)  # ollama | openai_compat
    base_url: str | None = Field(default=None, max_length=512)
    model_name: str = Field(max_length=128)
    api_key: str | None = None
    is_default: bool = False
    # 选内置服务商预设（如 deepseek）时，provider/base_url 缺省自动按目录补全
    provider_preset: str | None = Field(default=None, max_length=32)


class ModelConfigUpdate(BaseModel):
    label: str | None = Field(default=None, max_length=64)
    provider: str | None = Field(default=None, max_length=32)
    base_url: str | None = Field(default=None, max_length=512)
    model_name: str | None = Field(default=None, max_length=128)
    api_key: str | None = None
    is_default: bool | None = None
    # 选内置服务商预设（如 deepseek）时，provider/base_url 缺省自动按目录补全
    provider_preset: str | None = Field(default=None, max_length=32)


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


class ProviderPreset(BaseModel):
    """内置服务商预设：用于「添加模型」时自动带出 base_url 与模型名建议。"""

    key: str
    label: str
    provider: str
    base_url: str | None = None
    models: list[str] = []
    api_key_hint: str | None = None
    doc_url: str | None = None


class ModelListResp(BaseModel):
    builtin: list[BuiltinModelInfo]
    custom: list[ModelConfigResp]


class DefaultModelReq(BaseModel):
    id: uuid.UUID


def _to_resp(mc: ModelConfig) -> ModelConfigResp:
    """把 ModelConfig ORM 行转为对外响应（不含 api_key 明文）。"""
    return ModelConfigResp(
        id=mc.id,
        label=mc.label,
        provider=mc.provider,
        base_url=mc.base_url,
        model_name=mc.model_name,
        is_default=mc.is_default,
    )
