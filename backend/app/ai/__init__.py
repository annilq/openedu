"""app/ai —— Genkit 流式编排层（ADR-0015 / 迁移 08b：统一 Genkit 全栈）。

这是**唯一**允许 `import genkit` 的包（迁移后 GenkitProvider 作为 Genkit 适配层也在此边界内调用）。
业务/domain 代码统一经本包暴露的非流式入口（generate_question / grade_open / mock_question）
与流式 flow（tutor_ask / tasks_generate），框架 import 隔离延续 ADR-003。

为改善冷启动并让业务 SubAgent 包（app.ai.subagents）可在不加载 genkit 重型依赖的前提下被单测，
本包采用惰性导入：只有真正访问 genkit 相关符号时才加载 flows / engine。
"""

from __future__ import annotations

from typing import Any


# 惰性导入：避免仅使用 subagents / 非流式入口时也触发 genkit 重型依赖加载。
def __getattr__(name: str) -> Any:
    if name == "subagents":
        # ADR-0021：业务 SubAgent 包（导入即注册出题/伴学两个 SubAgent）。
        from app.ai import subagents

        return subagents
    if name == "mock_question":
        from app.ai import flows

        return flows._mock_question
    if name in {
        "generate_question",
        "generate_questions_stream",
        "grade_open",
        "tutor_stream",
        "QuestionSchema",
    }:
        from app.ai import flows

        return getattr(flows, name)
    if name in {"resolve_engine", "list_builtin_models", "EngineResolution"}:
        from app.ai import engine

        return getattr(engine, name)
    if name in {"flows", "engine"}:
        import importlib

        return importlib.import_module(f"app.ai.{name}")
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


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
    "subagents",
]
