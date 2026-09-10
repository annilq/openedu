"""agent_core —— 业务无关的通用 Agent 框架（ADR-0031）。

内部可安装包：把「协议 + subagent 注册 + subagent 路由 + 工具调用 + 统一事件流」抽象为
与业务解耦的内核。各业务工程 ``pip install agent_core`` 后，实现自己的 SubAgent 即可接入。

本包**零业务依赖**：不 import 任何 app.* 符号；模型/检索/安全均经 ``RuntimeDeps`` 注入。
"""
from __future__ import annotations

from agent_core.errors import AgentError, ToolExecutionError
from agent_core.protocol import (
    AssistantEvent,
    data_event,
    error,
    run_started,
    tool_call,
    tool_result,
)
from agent_core.registry import (
    SubAgentManifest,
    build_subagent,
    discover_subagent_manifests,
    get_subagent_class,
)
from agent_core.router import classify
from agent_core.runtime import AgentRuntime, RouteDecision
from agent_core.seams import (
    Chunk,
    LLMProvider,
    Retriever,
    RuntimeDeps,
    Safety,
    SafetyResult,
    StreamEvent,
    StructuredDone,
    TextDelta,
    ToolCall,
)
from agent_core.subagent import (
    BaseSubAgent,
    SubAgentContext,
    ToolCallPair,
    run_with_tools,
)
from agent_core.tools import ToolRegistry, ToolSpec

__all__ = [
    "AgentRuntime",
    "RouteDecision",
    "SubAgentManifest",
    "discover_subagent_manifests",
    "get_subagent_class",
    "build_subagent",
    "classify",
    "AssistantEvent",
    "data_event",
    "error",
    "run_started",
    "tool_call",
    "tool_result",
    "BaseSubAgent",
    "SubAgentContext",
    "ToolCallPair",
    "run_with_tools",
    "ToolSpec",
    "ToolRegistry",
    "LLMProvider",
    "Retriever",
    "Safety",
    "SafetyResult",
    "RuntimeDeps",
    "StreamEvent",
    "TextDelta",
    "ToolCall",
    "StructuredDone",
    "Chunk",
    "AgentError",
    "ToolExecutionError",
]
