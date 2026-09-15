"""Pydantic schemas for the model management feature."""

import uuid

from pydantic import BaseModel, Field, field_validator

from app.db.models import ModelConfig


class ModelConfigCreate(BaseModel):
    """新增模型请求（ADR-0039）：api_key **必填**。

    模型一律由家长手动录入、必须自带可用凭据——历史上允许 api_key 缺省，
    结果是存下一行解不开密钥的配置，直到用户提问时才以「模型不支持工具调用」
    之类的错误暴露（事故见 ADR-0038）。此处前置拦截：空 / 纯空白一律 422。
    """

    label: str = Field(max_length=64)
    # provider 选填：仅填 provider_preset 时可自动按目录补全；二者至少其一。
    provider: str | None = Field(default=None, max_length=32)  # ollama | openai_compat
    base_url: str | None = Field(default=None, max_length=512)
    model_name: str = Field(max_length=128)
    api_key: str = Field(min_length=1, max_length=2048)
    is_default: bool = False
    # 选内置服务商预设（如 deepseek）时，provider/base_url 缺省自动按目录补全
    provider_preset: str | None = Field(default=None, max_length=32)

    @field_validator("api_key")
    @classmethod
    def _api_key_not_blank(cls, value: str) -> str:
        """去空白后仍为空 → 拒绝（前端也可能传 ``" "``）。"""
        stripped = value.strip()
        if not stripped:
            raise ValueError("api_key 不能为空")
        return stripped


class ModelConfigUpdate(BaseModel):
    """改模型请求：字段全部可选，**不传 = 不修改**（含 api_key）。"""

    label: str | None = Field(default=None, max_length=64)
    provider: str | None = Field(default=None, max_length=32)
    base_url: str | None = Field(default=None, max_length=512)
    model_name: str | None = Field(default=None, max_length=128)
    api_key: str | None = Field(default=None, max_length=2048)
    is_default: bool | None = None
    # 选内置服务商预设（如 deepseek）时，provider/base_url 缺省自动按目录补全
    provider_preset: str | None = Field(default=None, max_length=32)

    @field_validator("api_key")
    @classmethod
    def _api_key_not_blank(cls, value: str | None) -> str | None:
        """不传 = 不修改；但传了就必须是非空白串（不允许用 ``" "`` 抹掉已有密钥）。"""
        if value is None:
            return None
        stripped = value.strip()
        if not stripped:
            raise ValueError("api_key 不能为空")
        return stripped


class ModelConfigResp(BaseModel):
    id: uuid.UUID
    label: str
    provider: str
    base_url: str | None
    model_name: str
    is_default: bool


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
    """家长可见的模型清单（ADR-0039：无内置模型，全部为自建）。"""

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
