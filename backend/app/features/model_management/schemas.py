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


class ModelProbeReq(BaseModel):
    """「测试连接」请求：一组**可能还没落库**的模型参数。

    两种用法：
    - 新增表单：只带 provider / base_url / model_name / api_key（parent 刚敲进去的明文）；
    - 编辑表单或列表页：带 ``model_id``，以库里已存的配置与**加密密钥**为底，
      其余字段只作覆盖（编辑时 API Key 留空 = 不修改，故必须用库里的那份去试）。

    ⚠️ ``api_key`` 是本端点唯一会收到明文密钥的入口：只在本次请求内使用，
    不落库、不进日志、不回显（响应体里没有任何密钥字段）。
    """

    model_id: uuid.UUID | None = None
    provider: str | None = Field(default=None, max_length=32)
    base_url: str | None = Field(default=None, max_length=512)
    model_name: str | None = Field(default=None, max_length=128)
    api_key: str | None = Field(default=None, max_length=2048)
    provider_preset: str | None = Field(default=None, max_length=32)


class ModelProbeResp(BaseModel):
    """「测试连接」结果：**结果即数据**，故连通失败也返回 200 + ``ok=false``。

    用 200 而不是 502，是因为「测不通」正是本端点要回答的正常结论之一——
    只有「参数不合法 / 模型不属于你」才走 4xx。``error_kind`` 直接沿用
    ADR-0038 的归因枚举（auth / rate_limit / network / bad_request / unknown）
    + ``timeout``，前端据此给出可操作的下一步（换密钥 / 改地址 / 换模型名）。
    """

    ok: bool
    latency_ms: int
    message: str  # 面向家长的单句结论
    error_kind: str | None = None
    detail: str | None = None  # 厂商原始原因（已脱敏、截断），供家长自行核对


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
