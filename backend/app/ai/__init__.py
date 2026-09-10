"""app/ai —— AI 编排层（ADR-0015 修订 / ADR-0032 收敛后）。

本包是跨 feature 的 AI runtime（ADR-0027 共享内核）：编排 subagents + 桥接 Genkit 引擎。

ADR-0032 Q3 后**教育出题业务已全部归位到** ``app.ai.subagents.question``
（``pipeline.py`` 出题管线 / ``parsers.py`` 契约与解析器），本包只留：
- ``engine``：模型引用 → 中性参数（ModelConfig / 解密 / settings）→ 适配器构造；
- ``model_catalog``：服务商产品预设；
- ``subagents``：业务 SubAgent 编排入口。

观测落库已由 ``app.features.assistant`` 统一承担（ADR-0026）；原 ``app/ai/debug_log.py``
在 ADR-0032 收敛中**删除**（零调用方的遗留件）。

Genkit 仅作为底层 LLM 引擎，其 SDK 构造收敛于 ``agent_core.adapters.genkit``；所有 AI
入口统一收敛到 ``POST /api/v1/assistant/chat``（ADR-0024）。

本包采用惰性导入（``__getattr__``）：只有真正访问相关符号时才加载 engine / subagents，
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
    if name == "generate_question":
        from app.ai.subagents.question.pipeline import generate_question

        return generate_question
    if name == "QuestionSchema":
        from app.ai.subagents.question.parsers import QuestionSchema

        return QuestionSchema
    if name in {"resolve_engine", "list_builtin_models", "EngineResolution"}:
        from app.ai import engine

        return getattr(engine, name)
    if name == "engine":
        import importlib

        return importlib.import_module("app.ai.engine")
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


__all__ = [
    "resolve_engine",
    "list_builtin_models",
    "EngineResolution",
    "generate_question",
    "QuestionSchema",
    "subagents",
]
