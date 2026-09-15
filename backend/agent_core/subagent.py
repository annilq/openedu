"""agent_core SubAgent 基类与共享上下文（业务无关）。

统一契约：``run(message, ctx) -> AsyncIterator[AssistantEvent]``（自由文本 → 异步产出
AG-UI 事件帧）。意图路由由 ``AgentRuntime`` 负责，各 SubAgent 只需实现自身的 ``run``。

- ``SubAgentContext`` 仅含业务无关字段；教育等业务的 subject/grade/focus 等走 ``extra``。
- ``BaseSubAgent.tools``（默认空）声明真实可调用工具；非空时 runtime 以 tool loop 调度
  （见 ``run_with_tools``）。``tools=[]`` 的 subagent 走一次性 ``run``（opt-in）。

**轮次与失败边界（ADR-0033 / ADR-0038）**：tool loop 受 ``BaseSubAgent.max_turns`` 保护（默认 3）。
失败分两类且**不得混用**：引擎不支持工具调用时由适配器抛 ``ToolUnsupportedError``，runtime 转
``ERROR(code="TOOL_UNSUPPORTED")`` 并中止；厂商拒绝请求（认证 / 限流 / 网络）时抛
``ProviderRequestError``，转 ``ERROR(code="PROVIDER_ERROR")`` 并中止。两者都是**硬失败**——
不静默降级为纯文本。
"""
from __future__ import annotations

import json
import re
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, AsyncIterator

from agent_core.errors import ProviderRequestError, ToolUnsupportedError
from agent_core.ports import (
    Hooks,
    LLMProvider,
    Retriever,
    StructuredDone,
    TextDelta,
    TextKind,
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


# 厂商拒绝请求时的**可操作**提示由 ``ProviderRequestError.user_hint`` 提供（ADR-0038）：
# 认证 / 限流 / 网络走策展文案，原始厂商报文只进日志（不泄露被拒凭据尾号）。


# 模型把工具调用「写成了文本」的判定：文本里出现工具调用协议标记，且点名了某个真实工具。
# 命中即视为模型未走原生 function calling（把调用叙述进了思考/正文），必须硬失败，
# 绝不能把这段原始协议当答案回流（ADR-0033：禁止静默降级为纯文本）。
_TOOL_CALL_PROTOCOL_RE = re.compile(
    r'(?:<invoke\s+name=|"name"\s*:\s*"|function_call|"function"\s*:\s*\{)',
    re.IGNORECASE,
)

# 工具型 subagent 收不到可用答复时的统一提示（两条路径共用：正文即协议 / 只有独白）。
# 文案必须给出**可执行出路**（换个模型 / 关掉思维链），只说「失败了」用户无从下手。
_UNSUPPORTED_TOOL_CALL_HINT = (
    "当前模型未以标准 function calling 返回工具调用（疑似将调用写成了文本/思维链），"
    "查询无法执行。请使用支持原生工具调用的模型，或在模型配置中关闭思维链后重试。"
)


def _text_looks_like_tool_call(text: str, tool_names: list[str]) -> bool:
    """文本是否伪装成了工具调用：含调用协议标记且点名了已注册工具。

    仅作「该不该硬失败」的粗筛——命中说明模型把 ``<invoke name="...">`` / JSON
    ``"name": "..."`` 这类调用式写进了文本而非产出原生 ``ToolCall`` 事件，此时继续把
    ``acc`` 当答案是把内部协议泄露给用户，故交由调用方判为 TOOL_UNSUPPORTED。
    """
    if not _TOOL_CALL_PROTOCOL_RE.search(text):
        return False
    return any(name and name in text for name in tool_names)


def _flushable_thinking(buffered: list[str], tool_names: list[str]) -> list[str]:
    """思考缓冲外发前的最后一道闸：整段命中调用协议则全部丢弃。

    思维链里出现 ``<invoke name="...">`` 这类**调用草稿**时，即便本轮已经正常产出原生
    ``ToolCall``（内容本身无害），把这些伪协议片段送进 SSE 也是把内部实现暴露给客户端。
    不变式：**原始调用协议永不出现在任何下发给客户端的事件里**（ADR-0033 / ADR-0043）。
    """
    if _text_looks_like_tool_call("".join(buffered), tool_names):
        return []
    return buffered


async def run_with_tools(
    agent: BaseSubAgent,
    message: str,
    ctx: SubAgentContext,
    *,
    session: Any = None,
    hooks: "Hooks | None" = None,
) -> AsyncIterator[Any]:
    """真实 tool loop 驱动（框架提供，subagent opt-in）。

    仅在 ``agent.tools`` 非空时调用：首轮把工具 schema 随请求发给模型；收到 ``ToolCall``
    → 执行 ``handler`` → 回灌工具结果 → 再请求，循环直到模型不再请求工具。
    每个阶段 yield 对应的 AG-UI 事件帧（THINKING / TOOL_CALL / TOOL_RESULT / ASSISTANT_MESSAGE）。

    三条边界（ADR-0033）与两类失败（ADR-0038）：

    - **轮次上限**：最多请求模型 ``agent.max_turns`` 次（默认 3），超限以
      ``ERROR(code="TOOL_TURN_LIMIT")`` 中止——杜绝「回灌丢失 → 模型反复重调」的无限循环。
    - **硬失败 · 模型能力**：引擎不支持工具调用时适配器抛 ``ToolUnsupportedError``，此处转
      ``ERROR(code="TOOL_UNSUPPORTED")`` 并中止，**不静默降级为纯文本**。
    - **硬失败 · 厂商拒绝**：认证失败 / 限流 / 网络不可达时适配器抛 ``ProviderRequestError``，
      此处转 ``ERROR(code="PROVIDER_ERROR")`` 并给出**可操作**提示（如「API Key 无效，请重新填写」）。
      两者必须分开：把 401 说成「不支持工具调用」会让用户去换模型，真问题是密钥。
    - **同轮多工具**：一轮内模型请求的多个工具全部执行后再回灌，不丢弃后续请求。

    **回灌契约**：每轮先入一条 ``{"role": "assistant", "tool_calls": [...]}`` 再入对应的
    ``{"role": "tool", "name", "ref", "content"}`` 结果（成对出现）——适配器据此重建
    provider 要求的 ToolRequest ↔ ToolResponse 配对。

    **推理与正文分流（ADR-0043）**：``TextDelta.kind`` 决定去向——``REASONING`` 只进
    思考缓冲（外发为 THINKING，且下发前过滤掉调用伪协议），``TEXT`` 才累进 ``acc``。
    因此「工具型 subagent 整轮没有原生 ``ToolCall`` 且正文为空」只剩一种解释：模型把调用
    意图留在了思维链里、没走原生 function calling——此时硬失败（TOOL_UNSUPPORTED），
    绝不把内部独白当答复下发（这正是真机上「英文独白被当答案」的结构性根因）。
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
    tool_names = [t.name for t in tools]
    # 是否已见过**原生** ToolCall。用于区分两种「本轮没有工具调用」：
    # 从没见过 = 模型走不了原生 function calling（能力问题，硬失败）；
    # 见过 = 模型只是这轮不调工具（如收尾轮没话说），不该误报能力缺陷。
    native_fc_seen = False

    for turn_idx in range(max_turns):
        acc = ""  # 本轮**正文**（只收 kind=TEXT；思维链另走 turn_thinking）
        turn_calls: list[dict] = []  # 本轮模型请求的工具（含 ref，供适配器重建 ToolRequest）
        results: list[dict] = []  # 本轮工具结果（须紧随上面的 assistant 条目入 history）
        # 本轮回显的思考缓冲（只收 kind=REASONING）：判定为「协议泄露」时整段丢弃。
        turn_thinking: list[str] = []

        # ── 生命周期钩子（可选，LLM 不可见，P2 extension seam） ──
        # before_turn：每轮 LLM 调用前可改写 (system, prompt, history)；异常被吞，回退原值。
        if hooks is not None:
            try:
                system, user, history = await hooks.before_turn(
                    turn=turn_idx, system=system, prompt=user, history=history
                )
            except Exception:  # noqa: BLE001 — 钩子故障不得影响主链路
                pass
        # rewrite_messages：发送前统一改写整段消息（如裁剪超大 tool result）；
        # 仅用于本次请求，不写回 canonical history，避免下一轮重复裁剪失真。
        send_history = history
        if hooks is not None:
            try:
                send_history = await hooks.rewrite_messages(messages=history)
            except Exception:  # noqa: BLE001
                send_history = history

        try:
            async for ev in agent.provider.stream(
                system, user, tools=registry.schemas(), history=send_history
            ):
                if isinstance(ev, TextDelta):
                    if ev.kind is TextKind.REASONING:
                        # 思维链（含模型写下的调用草稿）只作思考回显：**不进答案**（acc），
                        # 也**不进回灌历史**——回灌思维链会污染后续轮次（ADR-0043）。
                        turn_thinking.append(ev.delta)
                    else:
                        acc += ev.delta
                elif isinstance(ev, ToolCall):
                    native_fc_seen = True
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
                    # after_tool 钩子：改写工具结果（如截断超大结果），失败则保留原结果。
                    if hooks is not None:
                        try:
                            result = await hooks.after_tool(
                                name=ev.name, args=ev.args, result=result, tool_call_id=ref
                            )
                        except Exception:  # noqa: BLE001 — 钩子故障不得影响主链路
                            pass
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
        except ProviderRequestError as exc:
            yield error(exc.user_hint, code="PROVIDER_ERROR")
            return

        # 工具请求轮必须先入 history（成对不变量：assistant.tool_calls → tool 结果），
        # 否则适配器无法重建 provider 要求的 ToolRequest ↔ ToolResponse 配对。
        # 入历史的 content 是 acc（正文）——思维链不入历史（ADR-0043）。
        if turn_calls:
            for t in _flushable_thinking(turn_thinking, tool_names):
                yield thinking(t)
            history.append({"role": "assistant", "content": acc, "tool_calls": turn_calls})
            history.extend(results)
            continue

        # 本轮既无原生 ToolCall、也没有任何正文 —— 没有任何内容可答复。
        if not acc:
            if not native_fc_seen:
                # 从未成功走过原生 function calling：模型的「调用意图」全留在思维链里
                # （真机形态：英文独白 + ``<invoke>`` 草稿），而思维链绝不能当答案下发。
                # 唯一正确的行为是硬失败，而不是把内部独白当答复（ADR-0033 / ADR-0043）。
                yield error(_UNSUPPORTED_TOOL_CALL_HINT, code="TOOL_UNSUPPORTED")
                return
            # 之前轮次已成功调用过工具（数据卡已下发），本轮只是没有收尾话术——
            # 能力没问题，安静结束，不误报成「模型不支持工具调用」。
            return

        # 有正文，但正文里出现了已注册工具名的「调用式」写法（模型把工具调用写成了
        # 文本而非原生 ToolCall）：不能把这段原始协议当答案回流给用户（ADR-0033）。
        if _text_looks_like_tool_call(acc, tool_names):
            yield error(_UNSUPPORTED_TOOL_CALL_HINT, code="TOOL_UNSUPPORTED")
            return

        for t in _flushable_thinking(turn_thinking, tool_names):
            yield thinking(t)
        yield assistant_message(acc)
        return

    yield error(
        f"工具调用轮次超过上限（{max_turns} 次），已中止。", code="TOOL_TURN_LIMIT"
    )
