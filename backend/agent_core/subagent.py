"""agent_core SubAgent 基类与共享上下文（业务无关）。

统一契约：``run(message, ctx) -> AsyncIterator[AssistantEvent]``（自由文本 → 异步产出
AG-UI 事件帧）。意图路由由 ``AgentRuntime`` 负责，各 SubAgent 只需实现自身的 ``run``。

- ``SubAgentContext`` 仅含业务无关字段；教育等业务的 subject/grade/focus 等走 ``extra``。
- ``BaseSubAgent.tools``（默认空）声明真实可调用工具；非空时 runtime 以 tool loop 调度
  （见 ``run_with_tools``）。``tools=[]`` 的 subagent 走一次性 ``run``（opt-in）。

**轮次与失败边界（ADR-0033）**：tool loop 受 ``BaseSubAgent.max_turns`` 保护（默认 3），
引擎不支持工具调用时由适配器抛 ``ToolUnsupportedError``，runtime 转
``ERROR(code="TOOL_UNSUPPORTED")`` 并中止——**不静默降级为纯文本**。
"""
from __future__ import annotations

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, AsyncIterator

from agent_core.errors import ToolUnsupportedError
from agent_core.ports import (
    LLMProvider,
    Retriever,
    StructuredDone,
    TextDelta,
    ToolCall,
)
from agent_core.protocol import (
    assistant_message,
    error,
    thinking,
    tool_call,
    tool_result,
)
from agent_core.tools import ToolRegistry, ToolSpec


@dataclass
class SubAgentContext:
    """一次 SubAgent 调用的共享上下文（业务无关；业务字段走 extra）。"""

    role: str = ""                       # 调用者角色：parent | child
    message: str | None = None           # 用户原始输入
    history: list[dict] | None = None    # 多轮历史（[{role, content}]）
    model: str | None = None             # 请求的模型标识（透传用）
    skills: str = ""                     # 本业务 SOP 文本（manifest 发现注入）
    extra: dict[str, Any] = field(default_factory=dict)  # 业务自由扩展（subject/grade/focus...）


@dataclass
class ToolCallPair:
    """一次工具调用的事件对句柄：``call`` 与 ``result()`` 同名成对，调用方不可能写错位。"""

    name: str
    call: Any  # AssistantEvent（TOOL_CALL）

    def result(self, payload: Any) -> Any:
        return tool_result(self.name, payload)


class BaseSubAgent(ABC):
    # 业务键（注册表索引）：question / tutor / tasks / ...
    business: str = "base"

    def __init__(self, *, provider: LLMProvider, retriever: Retriever | None = None) -> None:
        # provider：消息级 LLM 抽象；retriever：可选知识库检索。
        self.provider = provider
        self.retriever = retriever
        # 实例级空列表（避免共享可变默认，且仅 opt-in 的 subagent 会在 __init__ 里覆写）。
        self.tools: list[ToolSpec] = []

    # 真实工具（opt-in）：非空时由 runtime 以 tool loop 调度。
    # 注意：BaseSubAgent 不是 dataclass，不能写 field(default_factory=...)（否则 tools
    # 会变成一个 Field 对象而非列表，导致 run_with_tools 迭代时报
    # "'Field' object is not iterable"）。实例级空列表在 __init__ 里初始化。
    tools: list[ToolSpec] = []

    # tool loop 轮次上限（ADR-0033）：防止「工具回灌丢失 → 模型反复重调」的无限循环烧 token。
    # 查询场景通常 1–2 跳（先定位孩子 → 再查明细）；需要更多跳的 subagent 自行覆写。
    max_turns: int = 3

    # ── 协议助手：把 tool_call/tool_result 同名成对不变量收口到基类 ──
    def _tool(self, name: str, *, label: str | None = None, args: dict | None = None) -> ToolCallPair:
        """创建工具调用句柄：已构造 TOOL_CALL 帧，result() 产出同名 TOOL_RESULT。"""
        return ToolCallPair(name=name, call=tool_call(name, label=label, args=args))

    def _finish(self, text: str, *, blocked: bool | None = None) -> Any:
        """收尾 ASSISTANT_MESSAGE 帧。"""
        return assistant_message(text, blocked=blocked)

    def render_tool_result(self, name: str, result: Any) -> list[Any]:
        """可选 hook：把工具结果转成**额外展示帧**（默认不产帧）。

        `TOOL_RESULT` 只存原始载荷（模型上下文 + 落库回放）；前端卡片走 `DATA` 帧渲染。
        查询类 subagent 覆写本方法，把结构化结果补发为 DATA 帧，使
        「TOOL_RESULT 存原始 + DATA 供渲染」双轨成立（ADR-0033，前端零改动）。
        """
        return []

    # SubAgent 可覆写：tool loop 的初轮系统/用户消息（默认 skills 作系统、message 作用户）。
    def initial_system(self, message: str, ctx: SubAgentContext) -> str:
        return ctx.skills or "你是一个乐于助人的助手。"

    def initial_user(self, message: str, ctx: SubAgentContext) -> str:
        return message

    @abstractmethod
    async def run(
        self, message: str, ctx: SubAgentContext, *, session: Any = None
    ) -> AsyncIterator[Any]:
        """悬浮助手入口：自由文本 → 异步产出 AG-UI 事件帧（AssistantEvent）。"""
        ...


async def run_with_tools(
    agent: BaseSubAgent,
    message: str,
    ctx: SubAgentContext,
    *,
    session: Any = None,
) -> AsyncIterator[Any]:
    """真实 tool loop 驱动（框架提供，subagent opt-in）。

    仅在 ``agent.tools`` 非空时调用：首轮把工具 schema 随请求发给模型；收到 ``ToolCall``
    → 执行 ``handler`` → 回灌工具结果 → 再请求，循环直到模型不再请求工具。
    每个阶段 yield 对应的 AG-UI 事件帧（THINKING / TOOL_CALL / TOOL_RESULT / ASSISTANT_MESSAGE）。

    三条边界（ADR-0033）：

    - **轮次上限**：最多请求模型 ``agent.max_turns`` 次（默认 3），超限以
      ``ERROR(code="TOOL_TURN_LIMIT")`` 中止——杜绝「回灌丢失 → 模型反复重调」的无限循环。
    - **硬失败**：引擎不支持工具调用时适配器抛 ``ToolUnsupportedError``，此处转
      ``ERROR(code="TOOL_UNSUPPORTED")`` 并中止，**不静默降级为纯文本**。
    - **同轮多工具**：一轮内模型请求的多个工具全部执行后再回灌，不丢弃后续请求。

    **回灌契约**：每轮先入一条 ``{"role": "assistant", "tool_calls": [...]}`` 再入对应的
    ``{"role": "tool", "name", "ref", "content"}`` 结果（成对出现）——适配器据此重建
    provider 要求的 ToolRequest ↔ ToolResponse 配对。
    """
    tools = agent.tools
    if not tools:
        # 无工具：直接走 subagent 自身的一次性 run（保持兼容）。
        async for ev in agent.run(message, ctx, session=session):
            yield ev
        return

    registry = ToolRegistry(tools)
    history: list[dict] = list(ctx.history or [])
    system = agent.initial_system(message, ctx)
    user = agent.initial_user(message, ctx)
    max_turns = max(1, int(getattr(agent, "max_turns", 3)))
    ref_seq = 0  # 工具调用关联 id 计数器（provider 侧 tool_call_id，须请求/结果同值）

    for _ in range(max_turns):
        acc = ""
        turn_calls: list[dict] = []  # 本轮模型请求的工具（含 ref，供适配器重建 ToolRequest）
        results: list[dict] = []  # 本轮工具结果（须紧随上面的 assistant 条目入 history）
        try:
            async for ev in agent.provider.stream(
                system, user, tools=registry.schemas(), history=history
            ):
                if isinstance(ev, TextDelta):
                    acc += ev.delta
                    yield thinking(ev.delta)
                elif isinstance(ev, ToolCall):
                    ref = f"call_{ref_seq}"
                    ref_seq += 1
                    turn_calls.append({"name": ev.name, "args": ev.args, "ref": ref})
                    yield tool_call(ev.name, args=ev.args)
                    spec = registry.get(ev.name)
                    if spec is None:
                        result: Any = {"error": f"unknown tool: {ev.name}"}
                    else:
                        try:
                            result = await spec.handler(ev.args, ctx=ctx, session=session)
                        except Exception as exc:  # noqa: BLE001 — 单工具异常不应让整条流崩
                            result = {"error": str(exc)}
                    yield tool_result(ev.name, result)
                    for frame in agent.render_tool_result(ev.name, result):
                        yield frame
                    # 回灌契约（适配器据 role=="tool" + ref 构造引擎侧 ToolResponse）：
                    # {"role": "tool", "name": <工具名>, "ref": <关联 id>, "content": <结果 JSON>}
                    results.append(
                        {
                            "role": "tool",
                            "name": ev.name,
                            "ref": ref,
                            "content": json.dumps(result, ensure_ascii=False, default=str),
                        }
                    )
                elif isinstance(ev, StructuredDone):
                    if ev.data is not None:
                        yield assistant_message(str(ev.data))
        except ToolUnsupportedError as exc:
            yield error(f"当前模型不支持工具调用：{exc.reason}", code="TOOL_UNSUPPORTED")
            return

        # 工具请求轮必须先入 history（成对不变量：assistant.tool_calls → tool 结果），
        # 否则适配器无法重建 provider 要求的 ToolRequest ↔ ToolResponse 配对。
        if turn_calls:
            history.append({"role": "assistant", "content": acc, "tool_calls": turn_calls})
            history.extend(results)
            continue

        if acc:
            yield assistant_message(acc)
        return

    yield error(
        f"工具调用轮次超过上限（{max_turns} 次），已中止。", code="TOOL_TURN_LIMIT"
    )
