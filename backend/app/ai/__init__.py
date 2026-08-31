"""app/ai —— Genkit 流式编排层（ADR-0015）。

这是**唯一**允许 `import genkit` 的包（类比原 `LangChainProvider` 作为 langchain 适配层）。
业务/domain 代码仍只依赖 `LLMProvider` ABC 与非流式路径（`MockProvider`/`LangChainProvider`），
框架 import 隔离延续 ADR-003。
"""
from __future__ import annotations

from app.ai.engine import EngineResolution, list_builtin_models, resolve_engine
from app.ai.flows import QuestionSchema, generate_questions_stream, tutor_stream

__all__ = [
    "resolve_engine",
    "list_builtin_models",
    "EngineResolution",
    "tutor_stream",
    "generate_questions_stream",
    "QuestionSchema",
]
