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


class UnverifiedAnswerError(AgentError):
    """业务自述「结论必须有据」却整轮未执行工具就产出了正文（ADR-0109）。

    与 :class:`ToolUnsupportedError` 是**两码事**，混用会把真问题指错方向：

    - 后者是**模型能力**问题——模型产不出原生 function calling，把调用意图写进了
      思维链或正文（那两种形态各有各的硬失败分支，见 ``run_with_tools`` 末段）；
    - 此处是**归属**问题——正文干干净净、没有任何调用协议痕迹，缺的只是数据支撑。
      此时更可能的成因是这句话本就不属于该业务（路由误判：「23+45 怎么算」被判给了
      任务学情），而不是这个模型不会调工具。

    runtime 捕获后**丢弃**这段正文（它从未进过事件轨，丢弃即等于它从未存在），
    换一个业务重新处理一次：

    - 换得出落点（路由原语在**排除当前业务**后仍给出一个过门控的候选）→ 换业务重来；
    - 换不出 → 退回 ``ERROR(TOOL_UNSUPPORTED)`` 原文。

    这与 ADR-0033「绝不静默降级」不冲突：静默降级是**放行**这段正文（用户拿到假
    数据还以为是真的）；重路由是**换人**——匿名正文永不下发，且交接过程在事件轨上
    显式可见（一条 routing 思考帧）。
    """

    def __init__(self, business: str = "", *, text: str = "") -> None:
        self.business = business
        self.text = text
        super().__init__(f"unverified answer from {business or 'agent'}")


class ToolUnsupportedError(AgentError):
    """当前引擎/模型不支持工具调用（ADR-0033）。

    由适配器在「Tool 注册失败 / ToolCall 解析失败 / 引擎根本不支持」时抛出。
    runtime 捕获后转译 ``ERROR(code="TOOL_UNSUPPORTED")`` 并**中止**——
    绝不静默降级为纯文本（否则模型会在没有数据的情况下编造业务结论）。
    """

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(f"tool calling unsupported: {reason}")
