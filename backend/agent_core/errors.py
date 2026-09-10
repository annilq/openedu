"""agent_core 公共异常。

业务无关：不引用任何 app.* 符号。
"""
from __future__ import annotations


class AgentError(RuntimeError):
    """Agent 运行期错误（统一事件流里以 ERROR 帧转译）。"""


class ToolExecutionError(AgentError):
    """工具执行失败。"""

    def __init__(self, tool: str, reason: str) -> None:
        self.tool = tool
        self.reason = reason
        super().__init__(f"tool {tool} failed: {reason}")


class ToolUnsupportedError(AgentError):
    """当前引擎/模型不支持工具调用（ADR-0033）。

    由适配器在「Tool 注册失败 / ToolCall 解析失败 / 引擎根本不支持」时抛出。
    runtime 捕获后转译 ``ERROR(code="TOOL_UNSUPPORTED")`` 并**中止**——
    绝不静默降级为纯文本（否则模型会在没有数据的情况下编造业务结论）。
    """

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(f"tool calling unsupported: {reason}")
