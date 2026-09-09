"""app/ai —— AI 编排层（ADR-0015 修订 / 迁移 08b：统一 Genkit 全栈后收敛）。

本包只暴露被各 SubAgent 复用的底层一次性生成能力（SSE 流式由 SubAgent 在事件层封装），不再注册 Genkit flow 端点：

- 出题：``generate_question``（一次性结构化输出）。
- 答疑：``_tutor_generate``（一次性讲解文本）。
- 批改：``grade_open``（开放题批改）。
- Mock：``mock_question``（确定性假数据，无 key 时闭环）。

Genkit 仅作为底层 LLM 引擎经 ``engine.genkit`` 调用，不再经 ``genkit_fastapi`` 暴露原生 action；
所有 AI 入口统一收敛到 ``POST /api/v1/assistant/chat``（ADR-0024）。

本包采用惰性导入（``__getattr__``）：只有真正访问相关符号时才加载 flows / engine / subagents，
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
    if name == "mock_question":
        from app.ai import flows

        return flows._mock_question
    if name in {
        "generate_question",
        "grade_open",
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
    "generate_question",
    "grade_open",
    "mock_question",
    "QuestionSchema",
    "subagents",
]
