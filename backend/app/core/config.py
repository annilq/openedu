import warnings
from typing import Literal, Self

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # 本地开发从仓库根目录的 .env 读取；容器内通过环境变量注入
    model_config = SettingsConfigDict(
        env_file=("../.env", ".env"),
        env_ignore_empty=True,
        extra="ignore",
    )

    API_V1_STR: str = "/api/v1"
    PROJECT_NAME: str = "娃娃学习App"
    SECRET_KEY: str = "changeme"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 8
    FASTAPI_ENV: Literal["development", "production"] | None = "development"
    # 家教自用，CORS 默认放开；部署到公网时收紧为平板 App 的来源
    CORS_ORIGINS: list[str] = ["*"]

    # SQLite 本地零依赖；生产改为 postgresql+psycopg://
    DATABASE_URL: str = "sqlite:///./app.db"

    @field_validator("DATABASE_URL", mode="before")
    @classmethod
    def _normalize_db_url(cls, value: str) -> str:
        database_url = str(value)
        for scheme in ("postgres://", "postgresql://"):
            if database_url.startswith(scheme):
                return database_url.replace(scheme, "postgresql+psycopg://", 1)
        return database_url

    # —— LLM / 出题引擎（可插拔，对应 ADR-003）——
    LLM_PROVIDER: str = "mock"  # mock | langchain | deepseek
    LLM_API_KEY: str = ""
    LLM_BASE_URL: str = ""  # 国产模型 OpenAI 兼容端点（混元/通义等）
    LLM_MODEL: str = ""
    LLM_TEMPERATURE: float = 0.3

    # DeepSeek 快捷配置：LLM_PROVIDER=deepseek 时读取，无需填 LLM_*
    DEEPSEEK_API_KEY: str = ""
    DEEPSEEK_BASE_URL: str = "https://api.deepseek.com"
    DEEPSEEK_MODEL: str = "deepseek-v4-flash"

    # —— 多模型接入（ADR-0015 / 票据 08）：Genkit 编排流式 flow ——
    # 内置模型清单（env JSON）：[{id,label,provider,model_name,base_url?}]
    #   provider ∈ {ollama, openai_compat}；base_url 缺省时 ollama 走 OLLAMA_BASE_URL。
    # 家长自定义模型落 ModelConfig 表（见 models.py），管理员内置模型走此处声明。
    OLLAMA_BASE_URL: str = "http://localhost:11434"
    DEFAULT_MODEL: str = ""  # 内置模型 id；为空时回退 LLM_PROVIDER 对应模型
    BUILTIN_MODELS: str = "[]"  # JSON 字符串，解析见 app/ai/model_registry.py
    MODEL_FALLBACK: str = "none"  # none | mock；仅 mock 时 provider 不可达静默回退 Mock
    MODEL_APIKEY_SECRET: str = ""  # Fernet 密钥，用于加密 ModelConfig.api_key

    # —— 三期 AI 伴学答疑（F-304 每日上限）——
    # MVP 以「每日消息条数」计上限；时长上限（如累计分钟）为后续增强项。
    TUTOR_DAILY_LIMIT: int = 50

    # —— 三期 教材知识库检索（T11 / AC-305 检索能力）——
    # mock/builtin = 内置自编知识点库（无版权风险，闭环可用）；
    # vector（预留）= 后续接入 embedding 向量库；未知值回退 mock 并告警。
    RETRIEVER_PROVIDER: str = "mock"

    def _check_default_secret(self, var_name: str, value: str | None) -> None:
        if value in (None, "", "changeme"):
            message = (
                f'The value of {var_name} is default/empty, '
                "please change it for deployments."
            )
            if self.FASTAPI_ENV == "development":
                warnings.warn(message, stacklevel=1)
            else:
                raise ValueError(message)

    @model_validator(mode="after")
    def _enforce_non_default_secrets(self) -> Self:
        self._check_default_secret("SECRET_KEY", self.SECRET_KEY)
        return self


settings = Settings()  # type: ignore
