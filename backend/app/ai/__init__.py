"""app/ai —— AI 编排层（ADR-0015 修订 / 迁移 08b：统一 Genkit 全栈后收敛）。

本包是跨 feature 的 AI runtime（ADR-0027 共享内核）：编排 subagents + 桥接 Genkit 引擎。
出题共享原语与脚手架集中在 ``app/ai/generation``（``generate_question`` + prompt/解析/安全闸门）；
答疑（``tutor``）与批改（``grade_open``）的真实 Genkit 调用收敛于 ``app/domain/genkit_provider``
（``LLMProvider`` 实现，桥接本包边界）。不再注册 Genkit flow 端点。

Genkit 仅作为底层 LLM 引擎经 ``engine.genkit`` 调用，不再经 ``genkit_fastapi`` 暴露原生 action；
所有 AI 入口统一收敛到 ``POST /api/v1/assistant/chat``（ADR-0024）。

本包采用惰性导入（``__getattr__``）：只有真正访问相关符号时才加载 generation / engine / subagents，
避免重型依赖在仅需单测 SubAgent 时被强制加载。
"""

from __future__ import annotations

from typing import Any


# 惰性导入：避免仅使用 subagents / 非流式入口时也触发 genkit 重型依赖加载。
def __getattr__(name: str) -> Any:
    if name == "subagents":
        # ADR-0021：业务 SubAgent 包（导入即注册出题/伴学两个 SubAgent）。
        from app.ai import subagents

        return subagents
    if name in {
        "generate_question",
        "QuestionSchema",
    }:
        from app.ai import generation

        return getattr(generation, name)
    if name in {"resolve_engine", "list_builtin_models", "EngineResolution"}:
        from app.ai import engine

        return getattr(engine, name)
    if name in {"generation", "engine"}:
        import importlib

        return importlib.import_module(f"app.ai.{name}")
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


__all__ = [
    "resolve_engine",
    "list_builtin_models",
    "EngineResolution",
    "generate_question",
    "QuestionSchema",
    "subagents",
]
