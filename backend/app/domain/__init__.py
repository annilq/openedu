import warnings

from app.core.config import settings
from app.domain.grader import Grader
from app.domain.langchain_provider import LangChainProvider
from app.domain.mock_provider import MockProvider
from app.domain.provider import GeneratedQuestion, LLMProvider
from app.domain.question_generator import QuestionGenerator
from app.domain.quota import (
    REASON_ASK_LIMIT,
    REASON_SUBJECT_SCOPE,
    REASON_TIME_LIMIT,
    SUBJECTS,
    check_quota,
    validate_quota_config,
)
from app.domain.tutor import TutorService

__all__ = [
    "LLMProvider",
    "GeneratedQuestion",
    "MockProvider",
    "LangChainProvider",
    "QuestionGenerator",
    "Grader",
    "TutorService",
    "build_provider",
    "SUBJECTS",
    "check_quota",
    "validate_quota_config",
    "REASON_ASK_LIMIT",
    "REASON_TIME_LIMIT",
    "REASON_SUBJECT_SCOPE",
]


def build_provider() -> LLMProvider:
    """按配置选择出题引擎实现；mock 模式无需安装 langchain。

    未知值（拼写错误等）回退 mock 并告警，保证服务始终可启动。
    """
    if settings.LLM_PROVIDER in ("langchain", "deepseek"):
        return LangChainProvider()
    if settings.LLM_PROVIDER != "mock":
        warnings.warn(
            f"未知 LLM_PROVIDER={settings.LLM_PROVIDER!r}，回退到 mock",
            stacklevel=2,
        )
    return MockProvider()
