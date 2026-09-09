import uuid

from sqlmodel import Field, SQLModel


class ModelConfig(SQLModel, table=True):
    """家长自定义模型（ADR-0015 / 票据 08）：仅家长可增删改，api_key 经 Fernet 加密。

    provider ∈ {ollama, openai_compat}；base_url 仅 openai_compat 自定义端点需要，
    ollama 缺省走 settings.OLLAMA_BASE_URL。is_default 标记家长默认模型。
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")
    label: str = Field(max_length=64)
    provider: str = Field(max_length=32)
    base_url: str | None = Field(default=None, max_length=512)
    model_name: str = Field(max_length=128)
    api_key_enc: str | None = Field(default=None, max_length=1024)
    is_default: bool = Field(default=False)
