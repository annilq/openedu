import warnings
from pathlib import Path
from typing import Literal, Self

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# 环境文件按**本文件位置**解析（backend/app/core/config.py → backend/），不依赖进程 CWD。
# 原先写相对路径 `("../.env", ".env")` 时，配置来源会随启动目录漂移：在 backend/ 里启动
# 读得到 backend/.env，在仓库根启动就读不到 —— 而 `.env` 里装着加密密钥
# `MODEL_APIKEY_SECRET`，读不到就静默回落默认值，已存 API Key 全部解不开（ADR-0038 同类事故）。
_BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    # 本地开发优先读取 backend/.env（仓库根目录 .env 作为兼容遗留，
    # 在元组中先加载、会被 backend/.env 覆盖，现已弃用，请勿依赖）。
    # 容器内通过环境变量注入（该目录下两个文件不存在时静默跳过）。
    model_config = SettingsConfigDict(
        env_file=(
            str(_BACKEND_DIR.parent / ".env"),  # 仓库根 .env（兼容遗留）
            str(_BACKEND_DIR / ".env"),  # backend/.env（首选，覆盖前者）
        ),
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

    # —— 多模型接入（ADR-0015 / ADR-0039）：Genkit 编排流式 flow ——
    # 所有引擎配置统一收敛到「模型管理」：模型一律由家长在客户端手动录入，落
    # ModelConfig 表（api_key 经 Fernet 加密），再于「模型管理」中「设为默认」。
    # （已移除：管理员内置模型目录 BUILTIN_MODELS，以及本地 LLM_PROVIDER /
    #   DEEPSEEK_* / LLM_* 等旁路 env —— 模型来源单点化，消除双份声明的漂移。）
    #   未配置任何模型时引擎解析返回 None，上层下发「未配置模型」提示，出题/答疑/批改不可用。
    OLLAMA_BASE_URL: str = "http://localhost:11434"
    MODEL_APIKEY_SECRET: str = ""  # Fernet 密钥，用于加密 ModelConfig.api_key（建议显式固定，见 ADR-0038）

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
