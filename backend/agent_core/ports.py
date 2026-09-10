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


# ───────────────────────── 运行时依赖注入包 ─────────────────────────
@dataclass
class RuntimeDeps:
    """一次请求所需的外部依赖，由业务层注入（业务无关，只认抽象）。

    - ``provider``：消息级 LLM（必填）。
    - ``retriever``：可选知识库。
    - ``safety``：可选输入安全闸门（路由前拦截）。
    - ``llm_classify``：可选意图分类器（弱意图领域可注入 LLM 分类；默认规则 + 启发式）。
    """

    provider: LLMProvider
    retriever: Retriever | None = None
    safety: Safety | None = None
    llm_classify: Callable[[str, list[str]], str] | None = None
