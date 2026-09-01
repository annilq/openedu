from app.domain.grader import Grader
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
from app.domain.retriever import (
    KnowledgeChunk,
    KnowledgeRetriever,
    MockKnowledgeRetriever,
    build_retriever,
)
from app.domain.tutor import TutorService

__all__ = [
    "LLMProvider",
    "GeneratedQuestion",
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
    "KnowledgeChunk",
    "KnowledgeRetriever",
    "MockKnowledgeRetriever",
    "build_retriever",
]


def build_provider() -> LLMProvider:
    """统一单栈：返回 GenkitProvider（Genkit 编排 + flow 内 mock 分支）。

    迁移 08b 后不再有 MockProvider / LangChainProvider 双栈分支——真实模型由
    GenkitProvider 内部 resolve_engine 解析，解析不到时自动走 flow 内确定性 mock 分支，
    保证服务始终可启动且零 key 闭环。

    GenkitProvider 延迟导入，避免 `app.domain` 与 `app.ai` 在包初始化期的循环依赖
    （app.ai.flows → app.crud → app.domain.*）。
    """
    from app.domain.genkit_provider import GenkitProvider

    return GenkitProvider()
