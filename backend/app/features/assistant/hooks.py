"""悬浮助手可用的生命周期钩子实现（扩展 seam 的即用组件，可选挂载）。

架构评审 P2 的动机之一：``工具结果过大自动截断`` / ``请求前注入租户级 system 约束`` /
``审计每轮 tool_call`` 这类 **LLM 不可见** 的事，应走统一挂载点而非改内核。

本模块提供即用实现；**默认不挂载**——``AgentRuntime`` 不传 ``hooks`` 即零行为。需要时在
``RuntimeDeps(hooks=...)`` 注入即可（如 ``RuntimeDeps(provider=..., hooks=TruncateOversizedToolResultHook())``）。
"""
from __future__ import annotations

from agent_core.ports import Hooks


class TruncateOversizedToolResultHook(Hooks):
    """工具结果超过阈值时就地截断，防止超大 tool result 撑爆上下文（仅作用于 ``after_tool``）。

    截断 ``content`` / ``text`` 字段（工具结果载荷的常见承载字段），超出 ``max_chars`` 部分
    替换为省略标记；其余字段与 system/prompt 不动，LLM 不可见。
    """

    def __init__(self, max_chars: int = 4000, ellipsis: str = "…(已截断)") -> None:
        self.max_chars = max_chars
        self.ellipsis = ellipsis

    async def after_tool(self, *, name, args, result, tool_call_id):
        if not isinstance(result, dict):
            return result
        out = dict(result)
        for key in ("content", "text"):
            val = out.get(key)
            if isinstance(val, str) and len(val) > self.max_chars:
                out[key] = val[: self.max_chars] + self.ellipsis
        return out


__all__ = ["TruncateOversizedToolResultHook"]
