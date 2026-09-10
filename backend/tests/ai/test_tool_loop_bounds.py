"""tool loop 边界契约（ADR-0033）：轮次上限 / 硬失败 / 回灌契约 / 渲染 hook。

覆盖 ``agent_core.subagent.run_with_tools`` 在「真有工具」路径下的三条边界，三者都是
此前缺失、且会造成**生产事故**的缺陷：

1. **轮次上限**：原实现是裸 ``while True``。适配器忽略 ``history`` 时工具回灌丢失，
   模型会反复重调同一工具 → 无限循环烧 token。现由 ``agent.max_turns`` 兜底。
2. **硬失败**：引擎不支持工具调用时**不得**静默降级为纯文本——那会让模型在没有数据的
   前提下编造业务结论（如「你共有 3 个任务、12 道题」）。改为 ``ERROR(TOOL_UNSUPPORTED)``。
3. **回灌契约**：工具结果必须以
   ``{"role": "tool", "name": ..., "ref": ..., "content": <JSON>}`` 入 history，且前面须有
   对应的 ``{"role": "assistant", "tool_calls": [...]}`` 条目（成对）——适配器才能重建
   provider 要求的 ToolRequest ↔ ToolResponse 配对，而非当成普通用户消息。

另覆盖：同轮多工具全部执行、未知工具/工具异常不崩流、``render_tool_result`` hook 出帧。

本文件不触真实模型（CI 红线）：provider 为脚本化替身，确定性可断言。
"""
from __future__ import annotations

import asyncio
import json

from agent_core.errors import ToolUnsupportedError
from agent_core.ports import LLMProvider, TextDelta, ToolCall
from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_ERROR,
    EVENT_THINKING,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
    data_event,
)
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools
from agent_core.tools import ToolSpec


class _ScriptedProvider(LLMProvider):
    """按脚本逐轮产出事件的确定性 provider（每轮 = 一次 ``stream`` 调用）。

    脚本站的一个元素：事件列表（正常产出）或 ``Exception`` 实例（抛出）。
    超出脚本范围的调用抛 ``AssertionError``——用于断言「不该再请求模型」。
    """

    def __init__(self, script: list) -> None:
        self.script = list(script)
        self.calls: list[dict] = []

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        self.calls.append(
            {"system": system, "prompt": prompt, "tools": tools, "history": list(history or [])}
        )
        if not self.script:
            raise AssertionError("provider 被调用的轮次超出脚本——轮次上限未生效")
        turn = self.script.pop(0)
        if isinstance(turn, Exception):
            raise turn
        for ev in turn:
            yield ev


class _Agent(BaseSubAgent):
    """最小可运行 subagent：仅用于驱动 tool loop。"""

    business = "loop_test"

    def __init__(self, *, provider, tools=(), max_turns=None, rendered=None) -> None:
        super().__init__(provider=provider)
        self.tools = list(tools)
        if max_turns is not None:
            self.max_turns = max_turns
        self._rendered = rendered
        self.rendered_calls: list[tuple[str, object]] = []

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        yield self._finish("来自一次性 run（无工具路径）")

    def render_tool_result(self, name, result):
        self.rendered_calls.append((name, result))
        if self._rendered is None:
            return []
        return [data_event(result, extra={"type": self._rendered})]


def _spec(name: str = "list_x", *, handler=None) -> ToolSpec:
    async def _default(args, *, ctx, session=None):
        return {"ok": True, "tool": name, "args": args}

    return ToolSpec(
        name=name,
        description=f"查询 {name}",
        schema={"type": "object", "properties": {"child_id": {"type": "string"}}},
        handler=handler or _default,
    )


async def _collect(agent, message="查一下", *, session=None, ctx=None):
    return [
        ev
        async for ev in run_with_tools(
            agent, message, ctx if ctx is not None else SubAgentContext(), session=session
        )
    ]


def _types(events) -> list[str]:
    return [ev.eventType for ev in events]


def _errors(events):
    return [ev for ev in events if ev.eventType == EVENT_ERROR]


# ── 轮次上限：模型永远要求调工具时，必须在 max_turns 处中止 ──
def test_max_turns_default_is_three():
    agent = _Agent(provider=_ScriptedProvider([]))
    assert agent.max_turns == 3
    assert BaseSubAgent.max_turns == 3


def test_tool_loop_aborts_at_max_turns():
    provider = _ScriptedProvider([[ToolCall(name="list_x")] for _ in range(3)])
    agent = _Agent(provider=provider, tools=[_spec()], max_turns=3)

    events = asyncio.run(_collect(agent))

    assert len(provider.calls) == 3, "应恰好请求模型 max_turns 次"
    assert _types(events).count(EVENT_TOOL_CALL) == 3
    assert _types(events).count(EVENT_TOOL_RESULT) == 3
    errs = _errors(events)
    assert len(errs) == 1
    assert errs[0].code == "TOOL_TURN_LIMIT"
    # 超限后不得再向模型请求（provider 会被 AssertionError 拦截，此处未被触发）


def test_turn_limit_is_configurable():
    provider = _ScriptedProvider([[ToolCall(name="list_x")] for _ in range(2)])
    agent = _Agent(provider=provider, tools=[_spec()], max_turns=2)

    events = asyncio.run(_collect(agent))

    assert len(provider.calls) == 2
    assert _errors(events)[0].code == "TOOL_TURN_LIMIT"


# ── 硬失败：不支持工具时显式报错，绝不降级成纯文本 ──
def test_tool_unsupported_is_hard_failure_and_stops():
    provider = _ScriptedProvider(
        [ToolUnsupportedError("model without function calling")]
    )
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    errs = _errors(events)
    assert len(errs) == 1
    assert errs[0].code == "TOOL_UNSUPPORTED"
    assert "不支持工具调用" in (errs[0].message or "")
    assert len(provider.calls) == 1, "硬失败后不得重试"
    # 关键：不得出现任何助手文本（否则就是静默降级、模型凭空空编业务数据）
    assert EVENT_ASSISTANT_MESSAGE not in _types(events)


# ── 正常路径：模型不再请求工具即收尾 ──
def test_loop_stops_when_model_stops_calling_tools():
    provider = _ScriptedProvider(
        [
            [ToolCall(name="list_x", args={"child_id": "c1"})],
            [TextDelta(delta="查到了 2 个任务。")],
        ]
    )
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    assert len(provider.calls) == 2
    assert EVENT_ERROR not in _types(events)
    texts = [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE]
    assert texts == ["查到了 2 个任务。"]
    # 首轮的文本增量走 THINKING
    assert EVENT_THINKING in _types(events)


# ── 回灌契约：assistant.tool_calls → tool 结果成对入 history，且第二轮能看见 ──
def test_tool_result_history_contract():
    provider = _ScriptedProvider(
        [[ToolCall(name="list_x", args={})], [TextDelta(delta="done")]]
    )
    agent = _Agent(provider=provider, tools=[_spec()])

    asyncio.run(_collect(agent))

    second = provider.calls[1]["history"]
    assert [e["role"] for e in second] == ["assistant", "tool"]
    request, entry = second
    assert [c["name"] for c in request["tool_calls"]] == ["list_x"]
    assert entry["name"] == "list_x"
    assert json.loads(entry["content"]) == {"ok": True, "tool": "list_x", "args": {}}
    # 关联 id 必须请求/结果同值——provider 侧 tool_call_id 靠它配对
    assert request["tool_calls"][0]["ref"] == entry["ref"]


def test_tool_refs_are_unique_across_turns():
    """跨轮 ref 不得重复：多轮各自 mint 新 id，否则 provider 会拒（id 冲突）。"""
    provider = _ScriptedProvider(
        [
            [ToolCall(name="list_x")],
            [ToolCall(name="list_x")],
            [TextDelta(delta="done")],
        ]
    )
    agent = _Agent(provider=provider, tools=[_spec()])

    asyncio.run(_collect(agent))

    refs = [
        c["ref"]
        for entry in provider.calls[2]["history"]
        if entry.get("tool_calls")
        for c in entry["tool_calls"]
    ]
    assert len(refs) == 2
    assert len(set(refs)) == 2


def test_tool_result_history_is_json_safe_for_non_serializable_values():
    """工具结果含 UUID/日期等非 JSON 原生类型时不得抛错（default=str 兜底）。"""
    from uuid import UUID

    async def _handler(args, *, ctx, session=None):
        return {"child_id": UUID("12345678-1234-5678-1234-567812345678")}

    provider = _ScriptedProvider(
        [[ToolCall(name="list_x")], [TextDelta(delta="done")]]
    )
    agent = _Agent(provider=provider, tools=[_spec(handler=_handler)])

    asyncio.run(_collect(agent))

    tool_entry = provider.calls[1]["history"][1]
    assert tool_entry["role"] == "tool"
    assert "12345678-1234-5678-1234-567812345678" in tool_entry["content"]


def test_initial_history_is_preserved_and_extended():
    provider = _ScriptedProvider(
        [[ToolCall(name="list_x")], [TextDelta(delta="done")]]
    )
    agent = _Agent(provider=provider, tools=[_spec()])
    ctx = SubAgentContext(history=[{"role": "user", "content": "上一轮提问"}])

    asyncio.run(_collect(agent, "本轮", ctx=ctx))

    assert provider.calls[0]["history"] == [{"role": "user", "content": "上一轮提问"}]
    assert provider.calls[1]["history"][0]["content"] == "上一轮提问"


# ── 同轮多工具：全部执行，不丢弃后续请求 ──
def test_multiple_tool_calls_in_one_turn_all_executed():
    provider = _ScriptedProvider(
        [
            [ToolCall(name="list_a"), ToolCall(name="list_b")],
            [TextDelta(delta="done")],
        ]
    )
    agent = _Agent(provider=provider, tools=[_spec("list_a"), _spec("list_b")])

    events = asyncio.run(_collect(agent))

    names = [ev.tool for ev in events if ev.eventType == EVENT_TOOL_RESULT]
    assert names == ["list_a", "list_b"]
    assert len(provider.calls) == 2, "同轮多工具应合并为一次回灌"
    # 一条 assistant（含两个 tool_calls）+ 两条 tool 结果
    second = provider.calls[1]["history"]
    assert [e["role"] for e in second] == ["assistant", "tool", "tool"]
    assert [c["name"] for c in second[0]["tool_calls"]] == ["list_a", "list_b"]


# ── 异常隔离：未知工具 / handler 抛错都不崩流 ──
def test_unknown_tool_becomes_error_payload_not_crash():
    provider = _ScriptedProvider(
        [[ToolCall(name="nope")], [TextDelta(delta="done")]]
    )
    agent = _Agent(provider=provider, tools=[_spec("list_x")])

    events = asyncio.run(_collect(agent))

    results = [ev.result for ev in events if ev.eventType == EVENT_TOOL_RESULT]
    assert results[0]["error"].startswith("unknown tool")
    assert EVENT_ERROR not in _types(events)


def test_handler_exception_becomes_error_payload_not_crash():
    async def _boom(args, *, ctx, session=None):
        raise RuntimeError("数据库炸了")

    provider = _ScriptedProvider(
        [[ToolCall(name="list_x")], [TextDelta(delta="done")]]
    )
    agent = _Agent(provider=provider, tools=[_spec(handler=_boom)])

    events = asyncio.run(_collect(agent))

    results = [ev.result for ev in events if ev.eventType == EVENT_TOOL_RESULT]
    assert "数据库炸了" in results[0]["error"]


def test_handler_receives_ctx_and_session():
    seen: dict = {}

    async def _handler(args, *, ctx, session=None):
        seen["role"] = ctx.role
        seen["session"] = session
        return {"ok": True}

    provider = _ScriptedProvider([[ToolCall(name="list_x")], [TextDelta(delta="d")]])
    agent = _Agent(provider=provider, tools=[_spec(handler=_handler)])
    ctx = SubAgentContext(role="child")

    asyncio.run(_collect(agent, "查", ctx=ctx, session="SESSION"))

    assert seen == {"role": "child", "session": "SESSION"}


# ── 渲染 hook：TOOL_RESULT 存原始 + hook 补发 DATA 卡 ──
def test_render_tool_result_hook_emits_extra_frames_after_tool_result():
    provider = _ScriptedProvider([[ToolCall(name="list_x")], [TextDelta(delta="done")]])
    agent = _Agent(provider=provider, tools=[_spec()], rendered="task")

    events = asyncio.run(_collect(agent))

    types = _types(events)
    data_idx = types.index(EVENT_DATA)
    result_idx = types.index(EVENT_TOOL_RESULT)
    assert result_idx < data_idx, "DATA 卡必须发在 TOOL_RESULT 之后"
    card = events[data_idx]
    assert card.data["type"] == "task"
    assert card.data["result"] == {"ok": True, "tool": "list_x", "args": {}}
    assert agent.rendered_calls == [("list_x", {"ok": True, "tool": "list_x", "args": {}})]


def test_render_hook_default_produces_no_frames():
    provider = _ScriptedProvider([[ToolCall(name="list_x")], [TextDelta(delta="done")]])
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    assert EVENT_DATA not in _types(events)
    # hook 恒被调用（基类默认返回空列表 → 不产帧），「不覆写」等于「不出卡」
    assert len(agent.rendered_calls) == 1


def test_base_render_hook_returns_empty_by_default():
    """基类实现直接调用（绕过 _Agent 覆写）→ 空列表，即默认不出卡。"""
    agent = _Agent(provider=_ScriptedProvider([]))

    assert BaseSubAgent.render_tool_result(agent, "x", {"a": 1}) == []


# ── 无工具路径保持兼容 ──
def test_no_tools_delegates_to_agent_run():
    provider = _ScriptedProvider([])  # 不该被调用
    agent = _Agent(provider=provider, tools=[])

    events = asyncio.run(_collect(agent))

    assert provider.calls == []
    assert [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE] == [
        "来自一次性 run（无工具路径）"
    ]
