"""agent_core 端口（ports）——业务无关的框架契约（六边形架构的「端口」）。

本模块是 agent_core 的「接口真相源」：任何业务工程接入时，只需实现这些抽象基类
（LLMProvider / Retriever / Safety）并注入 ``AgentRuntime``，即可复用整套路由 / 注册 /
统一事件流 / 工具循环。具体实现（如 genkit）作为「适配器」置于 ``agent_core/adapters/``。

**零业务依赖**：不 import 任何 app.* 符号，可独立发布为内部 PyPI 包。
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Callable


# ───────────────────────── 流式产出原语（provider → runtime） ─────────────────────────
@dataclass
class TextDelta:
    """模型产出的文本增量（推理 / 答复 token）。"""

    delta: str


@dataclass
class ToolCall:
    """模型请求调用某个工具（由 runtime 执行后回灌 tool_result）。"""

    name: str
    args: dict[str, Any] = field(default_factory=dict)


@dataclass
class StructuredDone:
    """结构化产出（schema 约束解码结果）。``data`` 为已解析的字典或对象。"""

    data: Any = None
    text: str | None = None


StreamEvent = TextDelta | ToolCall | StructuredDone


# ───────────────────────── LLM 抽象（消息级，不认识任何业务语义） ─────────────────────────
class LLMProvider(ABC):
    """统一 LLM 抽象：只认「消息」，不感知出题 / 答疑 / 批改等业务。

    业务 prompt 组装由 SubAgent 负责；本接口只负责把消息交给模型并流式回传。
    """

    @abstractmethod
    def stream(
        self,
        system: str,
        prompt: str,
        *,
        schema: Any | None = None,
        tools: list[Any] | None = None,
        history: list[dict] | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """流式产出。

        - ``schema`` 给定 → 约束解码，产出 ``TextDelta``（推理）+ 末帧 ``StructuredDone(data=解析字典)``。
        - ``tools`` 给定 → 模型可回 ``ToolCall``；runtime 执行后回灌并再请求。
        - 两者皆无 → 纯文本，逐段 ``TextDelta``，无 ``StructuredDone``。

        ``history`` 为多轮上下文，**必须被实现真正消费**（不消费会导致工具回灌丢失 →
        模型反复重调同一工具 → 死循环）。元素形态：

        - ``{"role": "user" | "assistant", "content": str}`` —— 普通对话轮次；
        - ``{"role": "assistant", "content": str, "tool_calls": [{"name": str, "args": dict,
          "ref": str}]}`` —— **模型发起的工具请求轮**。``ref`` 是工具调用的关联 id
          （引擎侧 ``tool_call_id``），必须与其后的工具结果条目同值；实现方据此构造
          ToolRequest part，**不得**把工具请求当成普通助手文本；
        - ``{"role": "tool", "name": str, "ref": str, "content": str}`` —— **工具结果回灌**
          （``content`` 为结果 JSON 文本；``ref`` 须与上一条 assistant 条目中对应调用的
          ``ref`` 相同）。实现方须据此构造引擎侧 ToolResponse part，而非当成普通用户消息。

        ``role == "assistant"`` 且带 ``tool_calls`` 的条目与其后的 ``tool`` 条目**必须成对
        出现**：多数函数调用协议（OpenAI / Anthropic 等）都要求工具结果回应前一条助手的
        工具请求，缺一侧会被端点直接拒绝。

        工具调用不受支持时（注册失败 / 无法解析 tool request / 引擎无此能力）**必须抛**
        ``ToolUnsupportedError``，不得静默降级为纯文本（ADR-0033）。
        """
        ...


# ───────────────────────── 知识库检索抽象（可选） ─────────────────────────
@dataclass
class Chunk:
    """一段检索命中内容（业务可自由扩展元数据）。"""

    content: str
    metadata: dict[str, Any] = field(default_factory=dict)


class Retriever(ABC):
    """可选知识库检索。签名业务无关：仅接受查询，返回文本块。"""

    @abstractmethod
    def retrieve(self, query: str, *, top_k: int = 5) -> list[Chunk]:
        ...


# ───────────────────────── 安全闸门抽象（可选注入） ─────────────────────────
@dataclass
class SafetyResult:
    safe: bool
    reason: str | None = None


class Safety(ABC):
    """输入 / 输出安全闸门。具体实现由业务注入（如儿童双层防护）。"""

    @abstractmethod
    def check_input(self, text: str) -> SafetyResult:
        ...

    def check_output(self, text: str) -> SafetyResult:
        """默认放行输出；业务可覆写。"""
        return SafetyResult(safe=True)


# ───────────────────────── 生命周期钩子（可选，LLM 不可见） ─────────────────────────
class Hooks:
    """后台扩展钩子（extension seam，对应参考架构 pi-coding-agent 的 lifecycle hooks）。

    全部方法默认空操作；业务继承后只覆写需要的一个或多个即可。agent_core 在 tool loop 的
    固定阶段调用它们，用于审计、裁剪、注入约束等**模型不可见**的干预（不污染 system/prompt
    的「业务语义」，除非 ``before_turn`` 显式改写）。

    健壮性：``run_with_tools`` 在调用处保证 ``hooks is None`` 时完全不触发，且钩子抛异常被
    吞掉（不影响主链路）——遵循评审「扩展置于后台，不改 LLM 上下文」的原则。

    三个固定点：

    - ``before_turn``：每轮 LLM 调用前触发，可改写 ``(system, prompt, history)`` 后返回。
    - ``after_tool``：工具执行后触发，返回改写后的 result 载荷（如截断超大 tool result）。
    - ``rewrite_messages``：发送前统一改写整段消息（如裁剪历史中的超大 tool result）。
    """

    async def before_turn(
        self, *, turn: int, system: str, prompt: str, history: list[dict]
    ) -> tuple[str, str, list[dict]]:
        """每轮 LLM 调用前触发；可改写并返回 ``(system, prompt, history)``。"""
        return system, prompt, history

    async def after_tool(
        self, *, name: str, args: dict, result: Any, tool_call_id: str
    ) -> Any:
        """工具执行后触发；返回改写后的 result 载荷（默认原样返回）。"""
        return result

    async def rewrite_messages(self, *, messages: list[dict]) -> list[dict]:
        """发送前统一改写整段消息（默认原样返回）。"""
        return messages


# ───────────────────────── 运行时依赖注入包 ─────────────────────────
@dataclass
class RuntimeDeps:
    """一次请求所需的外部依赖，由业务层注入（业务无关，只认抽象）。

    - ``provider``：消息级 LLM（必填）。
    - ``retriever``：可选知识库。
    - ``safety``：可选输入安全闸门（路由前拦截）。
    - ``llm_classify``：可选意图分类器（弱意图领域可注入 LLM 分类；默认规则 + 启发式）。
    - ``hooks``：可选生命周期钩子（扩展 seam，参考评审 P2）；``None`` 表示不挂载。
    """

    provider: LLMProvider
    retriever: Retriever | None = None
    safety: Safety | None = None
    llm_classify: Callable[[str, list[str]], str] | None = None
    hooks: Hooks | None = None
