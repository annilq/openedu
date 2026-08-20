import warnings

from app.core.config import settings
from app.domain.grader import Grader
from app.domain.langchain_provider import LangChainProvider
from app.domain.mock_provider import MockProvider
from app.domain.provider import GeneratedQuestion, LLMProvider
from app.domain.question_generator import QuestionGenerator
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
