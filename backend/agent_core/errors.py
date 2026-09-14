"""agent_core 公共异常。

业务无关：不引用任何 app.* 符号。
"""
from __future__ import annotations

from typing import ClassVar


class AgentError(RuntimeError):
    """Agent 运行期错误（统一事件流里以 ERROR 帧转译）。"""


class ToolExecutionError(AgentError):
    """工具执行失败。"""

    def __init__(self, tool: str, reason: str) -> None:
        self.tool = tool
        self.reason = reason
        super().__init__(f"tool {tool} failed: {reason}")


class ProviderRequestError(AgentError):
    """引擎调用失败：认证 / 限流 / 网络 / 请求被拒（ADR-0038）。

    与 ``ToolUnsupportedError`` 是**两码事**，不得混用：前者是「厂商拒绝了这次请求」，
    后者是「这个模型没有 function calling 能力」。历史 bug 把任意厂商异常都归成
    「不支持工具调用」，于是 401 认证失败被报成「当前模型不支持工具调用」，
    根因被彻底指错方向（事故见 ADR-0038）。

    ``kind`` 由适配器按厂商错误文本归类：``auth`` | ``rate_limit`` | ``network`` |
    ``bad_request`` | ``unknown``；runtime 转 ``ERROR(code="PROVIDER_ERROR")`` 并中止
    （拿不到数据就不得继续，同 ADR-0033 的硬失败精神）。

    ``user_hint`` 是**给用户看**的提示：认证 / 限流 / 网络三类走策展文案（可操作、
    不泄露凭据），其余回落到原始原因（便于定位）。原始厂商报文只进日志——它既冗长
    （整段 JSON），又可能带上被拒凭据的尾号（``Your api key: ****xOOR``）。
    """

    _HINTS: ClassVar[dict[str, str]] = {
        "auth": "模型认证失败：API Key 无效或已过期，请在「模型管理」中重新填写该模型的密钥。",
        "rate_limit": "模型服务限流：请求过于频繁，请稍后重试。",
        "network": "模型服务不可达：请检查网络与该模型的接口地址后重试。",
    }

    def __init__(self, reason: str, *, kind: str = "unknown") -> None:
        self.reason = reason
        self.kind = kind
        super().__init__(f"provider request failed ({kind}): {reason}")

    @property
    def user_hint(self) -> str:
        """面向用户的单句提示（策展文案优先，未知类别带原始原因）。"""
        return self._HINTS.get(self.kind) or f"模型调用失败：{self.reason}"


class ToolUnsupportedError(AgentError):
    """当前引擎/模型不支持工具调用（ADR-0033）。

    由适配器在「Tool 注册失败 / ToolCall 解析失败 / 引擎根本不支持」时抛出。
    runtime 捕获后转译 ``ERROR(code="TOOL_UNSUPPORTED")`` 并**中止**——
    绝不静默降级为纯文本（否则模型会在没有数据的情况下编造业务结论）。
    """

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(f"tool calling unsupported: {reason}")
