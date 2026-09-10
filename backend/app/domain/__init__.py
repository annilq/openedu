from typing import TYPE_CHECKING

from app.domain.grader import Grader
from app.domain.provider import GeneratedQuestion, LLMProvider
from app.domain.quota import (
    REASON_ASK_LIMIT,
    REASON_SUBJECT_SCOPE,
    REASON_TIME_LIMIT,
    SUBJECTS,
    QuotaLimits,
    check_quota,
    resolve_quota_limits,
    validate_quota_config,
)
from app.domain.retriever import (
    KnowledgeChunk,
    KnowledgeRetriever,
    MockKnowledgeRetriever,
    build_retriever,
)
from app.domain.tutor import TutorService

if TYPE_CHECKING:  # 避免 app.domain ↔ app.ai 包初始化期循环依赖
    from app.ai.engine import EngineResolution

__all__ = [
    "LLMProvider",
    "GeneratedQuestion",
    "Grader",
    "TutorService",
    "build_provider",
    "SUBJECTS",
    "check_quota",
    "validate_quota_config",
    "resolve_quota_limits",
    "QuotaLimits",
    "REASON_ASK_LIMIT",
    "REASON_TIME_LIMIT",
    "REASON_SUBJECT_SCOPE",
    "KnowledgeChunk",
    "KnowledgeRetriever",
    "MockKnowledgeRetriever",
    "build_retriever",
]


def build_provider(engine: "EngineResolution | None" = None) -> LLMProvider:
    """统一单栈：返回 GenkitProvider（Genkit 仅作底层 LLM 引擎）。

    迁移 08b 退役 LangChainProvider / MockProvider 双栈；真实模型由 GenkitProvider
    内部 resolve_engine 解析，解析不到（未配置 LLM_PROVIDER / 无 key）时出题 / 伴学返回
    None、批改抛错，由上层决定降级（不再提供确定性 mock 兜底，需真实引擎才能出题 / 答疑 / 批改）。

    ADR-0030：``engine`` 为由调用方（AgentRuntime）解析好的显式引擎（家长 ModelConfig /
    请求级 model）。传入则全程使用该引擎，``None`` 时回退全局解析。

    GenkitProvider 延迟导入，避免 `app.domain` 与 `app.ai` 在包初始化期的循环依赖
    （app.ai.generation → app.domain.*）。
    """
    from app.domain.genkit_provider import GenkitProvider

    return GenkitProvider(engine=engine)
