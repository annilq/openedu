"""app/ai —— Genkit 流式编排层（ADR-0015 / 迁移 08b：统一 Genkit 全栈）。

这是**唯一**允许 `import genkit` 的包（迁移后 GenkitProvider 作为 Genkit 适配层也在此边界内调用）。
业务/domain 代码统一经本包暴露的非流式入口（generate_question / grade_open / mock_question）
与流式 flow（tutor_ask / tasks_generate），框架 import 隔离延续 ADR-003。
"""
from __future__ import annotations

from app.ai.engine import EngineResolution, list_builtin_models, resolve_engine
from app.ai.flows import (
    QuestionSchema,
    generate_question,
    generate_questions_stream,
    grade_open,
    tutor_stream,
)
from app.ai.flows import (
    _mock_question as mock_question,
)

__all__ = [
    "resolve_engine",
    "list_builtin_models",
    "EngineResolution",
    "tutor_stream",
    "generate_questions_stream",
    "generate_question",
    "grade_open",
    "mock_question",
    "QuestionSchema",
]
