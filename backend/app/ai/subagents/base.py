"""业务 SubAgent 基类与共享上下文（ADR-0021）。

每个业务 SubAgent 暴露统一契约 ``handle(intent, ctx) -> result``，使轻主管（路由显式派发）
能无差别地调用任意业务；未来也可平滑插入 LLM 意图分类升级为完整 supervisor，
无需改动各 SubAgent 实现。
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any

from app.ai.runtime.protocol import assistant_message, tool_call, tool_result


@dataclass
class SubAgentContext:
    """一次 SubAgent 调用的共享上下文。学科 persona 由 SubAgent 内部据 subject 取，无需外部传。"""

    role: str = ""  # 调用者角色：parent | child（角色感知用，ADR-0026）
    subject: str = ""
    grade: int = 0
    knowledge_point: str = ""
    context: str | None = None
    question: str | None = None
    child_id: object | None = None
    parent_id: object | None = None
    model: str | None = None
    allowed_subjects: list[str] | None = None
    # WF-4 兴趣题模式：显式聚焦主题列表（如「恐龙」「太空」），由出题 SubAgent 注入出题
    # prompt，让题目情境围绕该主题展开（ADR-0024 经 /assistant/chat 的 focus_interest 字段透传）。
    focus_interest: list[str] | None = None
    # ADR-0026：服务端多轮——本会话已发生的对话历史（[{role, content}, ...]），
    # 由 runtime 从 Conversation/Message 载入后注入，供 SubAgent 透传给 provider 拼入 prompt。
    history: list[dict] | None = None
    extra: dict[str, Any] = field(default_factory=dict)


@dataclass
class ToolCall:
    """一次工具调用的事件对句柄（ADR：BaseSubAgent 深化）。

    ``tool_call`` 与 ``tool_result`` 必须共用同一 ``tool`` 名且语义成对；
    本句柄把名字收为单一来源，调用方不可能写出错位的帧：

        tc = self._tool("tutor_explain", label="伴学答疑")
        yield tc.call            # TOOL_CALL
        result = await self.service.aexplain(...)
        yield tc.result({"blocked": result.blocked})   # 同名 TOOL_RESULT
    """

    name: str
    call: "object"  # AssistantEvent（TOOL_CALL）

    def result(self, payload: Any) -> "object":
        """产出与 call 同名的 TOOL_RESULT 帧。"""
        return tool_result(self.name, payload)


class BaseSubAgent(ABC):
    # 业务键（注册表索引）：question / tutor / grader / diagnosis / planner / report …
    business: str = "base"

    def __init__(self, *, provider, retriever=None, engine=None) -> None:
        # provider: 业务层统一 LLM 抽象（LLMProvider）；retriever: 可选知识库检索。
        # engine: 可选的显式引擎（路由带 session 解析出的 ModelConfig 自定义模型）；
        #         为 None 时由 provider 自行解析，保证零破坏。
        self.provider = provider
        self.retriever = retriever
        self.engine = engine

    # ── 协议助手：（深）把「tool_call/tool_result 同名成对」不变量收口到基类 ──
    def _tool(self, name: str, *, label: str | None = None, args: dict | None = None) -> ToolCall:
        """创建工具调用句柄：已构造 TOOL_CALL 帧，result() 产出同名 TOOL_RESULT。"""
        return ToolCall(name=name, call=tool_call(name, label=label, args=args))

    def _finish(self, text: str, *, blocked: bool | None = None) -> "object":
        """收尾 ASSISTANT_MESSAGE 帧（各 subagent 统一收尾语义，便于未来集中增强）。"""
        return assistant_message(text, blocked=blocked)

    @abstractmethod
    async def handle(self, intent: dict, ctx: SubAgentContext) -> Any:
        """处理一次业务请求，返回业务结果（类型由子类定义）。"""
        ...

    @abstractmethod
    async def run(self, message: str, ctx: SubAgentContext, *, session=None) -> Any:
        """悬浮助手入口：自由文本 → 异步产出 AG-UI 事件帧（AssistantEvent）。

        ``session`` 为可选 DB 会话（查询类 subagent 用于落库/读取）。
        返回类型约定为 AsyncIterator[AssistantEvent]；子类用 ``yield`` 产出事件。
        """
        ...
