"""AgentRuntime 单例：文件夹发现仅执行一次（``AgentRuntime.discover()``）。

各 feature 的 service 通过 ``get_runtime()`` 取同一进程内单例，消除此前在
``app/features/{assistant,tasks}`` 各自复制的 ``_RUNTIME`` 模块级缓存（同构泄漏）。

单测时把桩 ``AgentRuntime`` 注入到 service 函数的 ``runtime=...`` 可选参数，
无需触发真实 ``discover()`` 与任何 HTTP 链路。
"""
from __future__ import annotations

from agent_core.runtime import AgentRuntime

_RUNTIME: AgentRuntime | None = None


def get_runtime() -> AgentRuntime:
    """返回进程内唯一的 AgentRuntime；首次调用时才执行 subagent 文件夹发现。"""
    global _RUNTIME
    if _RUNTIME is None:
        # agent_core 默认根即 backend/app/ai/subagents（module_base="app.ai.subagents"）
        _RUNTIME = AgentRuntime.discover()
    return _RUNTIME
