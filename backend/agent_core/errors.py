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
