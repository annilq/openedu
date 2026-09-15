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
from agent_core.ports import LLMProvider, TextDelta, TextKind, ToolCall
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
    # 正文只走 ASSISTANT_MESSAGE；本轮没有思维链，故不应出现 THINKING 帧（ADR-0043）
    assert EVENT_THINKING not in _types(events)


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


# ── 防护：模型把工具调用写成文本/XML 而非原生 ToolCall 时，不得把原始协议当答案泄露 ──
def test_text_tool_call_protocol_is_not_leaked_as_answer():
    """回归：模型本应发起原生 function calling，却把 ``<invoke name="...">`` 写进正文。

    旧实现会把这段原始协议随 ``assistant_message`` 直接回流给用户（暴露内部工具调用
    格式、且未真正执行查询）。现在应判为 TOOL_UNSUPPORTED 硬失败，绝不泄露原始协议。
    """
    leaked = (
        'Let me call the tool.<invoke name="list_x">'
        '<parameter name="child_id" string="true">c1</parameter></invoke>'
    )
    provider = _ScriptedProvider([[TextDelta(delta=leaked)]])
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    errs = _errors(events)
    assert len(errs) == 1
    assert errs[0].code == "TOOL_UNSUPPORTED"
    # 关键：不得出现任何助手文本——原始协议不能落到用户面前
    assert EVENT_ASSISTANT_MESSAGE not in _types(events)
    assert leaked not in "".join(
        ev.text or "" for ev in events if ev.eventType == EVENT_THINKING
    )


# ── 防护不误伤：普通文本收尾（无调用协议标记）仍正常作为答案 ──
def test_plain_text_answer_without_protocol_marker_passes_through():
    provider = _ScriptedProvider([[TextDelta(delta="我只查学习数据，无法帮你写诗。")]])
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    assert EVENT_ERROR not in _types(events)
    texts = [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE]
    assert texts == ["我只查学习数据，无法帮你写诗。"]


# ── 防护：模型**编造工具名**时的协议泄露（真机形态，2026-09-15） ──
def _fabricated_call_draft() -> str:
    """真机原文：模型把调用写成 XML，且工具名是**编的**（真实工具名另有其名）。"""
    return (
        '<invoke name="get_mistakes">\n'
        '<parameter name="child_id">a13be10f-e02c-4169-929f-2088b505f3d0</parameter>\n'
        "</invoke>"
    )


def test_fabricated_tool_name_is_not_leaked_as_answer():
    """回归（真机形态）：协议标记命中但点名的工具**未注册**，也绝不能放行。

    旧判定要求「协议标记命中 **且** 点名已注册工具」，模型把 ``list_wrong_questions``
    写成 ``get_mistakes`` 时第二条必然落空 → 整段 XML 原文随 ``assistant_message``
    下发给了用户。调用外壳是结构性字面量，与工具名无关，命中即须硬失败。
    """
    leaked = _fabricated_call_draft()
    provider = _ScriptedProvider([[TextDelta(delta=leaked)]])
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    errs = _errors(events)
    assert [e.code for e in errs] == ["TOOL_UNSUPPORTED"]
    # 未成功调过任何工具 → 走「查询无法执行」文案
    assert "查询无法执行" in (errs[0].message or "")
    assert EVENT_ASSISTANT_MESSAGE not in _types(events), "协议原文不得作为答案下发"
    assert leaked not in "".join(ev.text or "" for ev in events)


def test_fabricated_tool_name_after_successful_call_reports_partial():
    """已成功调过工具（数据卡已下发）后，收尾轮写成调用式 → 报「部分成功」。

    说「查询无法执行」与用户所见不符（卡片就在上面），会让人以为一条都没查到。
    """
    leaked = _fabricated_call_draft()
    provider = _ScriptedProvider(
        [[ToolCall(name="list_x", args={})], [TextDelta(delta=leaked)]]
    )
    agent = _Agent(provider=provider, tools=[_spec()], rendered="child")

    events = asyncio.run(_collect(agent))

    types = _types(events)
    # 第一轮的调用与其数据卡照常下发（查询本身是成功的）
    assert EVENT_TOOL_CALL in types and EVENT_TOOL_RESULT in types and EVENT_DATA in types
    errs = _errors(events)
    assert [e.code for e in errs] == ["TOOL_UNSUPPORTED"]
    assert "已给出本次查到的数据" in (errs[0].message or "")
    assert "查询无法执行" not in (errs[0].message or "")
    assert EVENT_ASSISTANT_MESSAGE not in types
    assert leaked not in "".join(ev.text or "" for ev in events)


def test_fabricated_call_draft_in_reasoning_is_dropped():
    """思考缓冲里的编造名调用草稿同样不得外发（协议永不出现于任何事件）。"""
    leaked = _fabricated_call_draft()
    provider = _ScriptedProvider(
        [
            [
                ToolCall(name="list_x"),
                TextDelta(delta=f"我先调用工具：{leaked}", kind=TextKind.REASONING),
            ],
            [TextDelta(delta="查到 2 个任务。")],
        ]
    )
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    assert EVENT_THINKING not in _types(events), "含调用伪协议的思考须整段丢弃"
    assert leaked not in "".join(ev.text or "" for ev in events)
    assert [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE] == [
        "查到 2 个任务。"
    ]


def test_weak_marker_without_registered_tool_name_is_plain_text():
    """防误伤：``"name": "`` 可能与正文同形（讲解 JSON 结构），无已注册工具名时照常放行。"""
    answer = '返回的字段长这样：{"name": "小明", "score": 90}，score 是掌握度。'
    provider = _ScriptedProvider([[TextDelta(delta=answer)]])
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    assert EVENT_ERROR not in _types(events)
    assert [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE] == [answer]


# ── 推理与正文分流（ADR-0043）：思维链不进答案、不进历史、外发前过滤伪协议 ──
def _plain_monologue() -> str:
    """真机形态的内部独白：**不含**任何调用协议标记的英文思考。

    这是旧防护漏掉的那一类：「只认 ``<invoke name=`` / ``"name": "`` 等协议标记」的启发式
    对纯自然语言独白完全无效，于是它被当作最终答案下发（用户看到一段英文思考）。
    """
    return (
        "Need child_id for lsc. Then query wrong questions. Let me call the tool. "
        "What is the tool name? Probably list_x. I shouldn't guess tool names... but I need to."
    )


def test_reasoning_only_turn_with_tools_hard_fails_instead_of_leaking_monologue():
    """回归（真机形态）：模型不发原生 ToolCall，把调用意图全留在思维链里。

    旧实现：适配器把 REASONING / TEXT 段一律当 ``TextDelta``，``run_with_tools`` 又全部
    累进 ``acc`` → 模型没产出原生工具调用时，这段**内部独白**被 ``assistant_message(acc)``
    直接下发给用户。旧防护对此无效——它只认协议标记，而独白是纯自然语言。
    现在思维链只进思考缓冲，正文为空即硬失败，一个字都不外泄。
    """
    leaked = _plain_monologue()
    provider = _ScriptedProvider([[TextDelta(delta=leaked, kind=TextKind.REASONING)]])
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    assert [e.code for e in _errors(events)] == ["TOOL_UNSUPPORTED"]
    assert EVENT_ASSISTANT_MESSAGE not in _types(events), "独白不得作为答案下发"
    # 关键：整段独白不得出现在任何事件的文本里（含 THINKING 帧）
    assert leaked not in "".join(ev.text or "" for ev in events)
    assert len(provider.calls) == 1, "硬失败后不得重试"


def test_reasoning_is_echoed_as_thinking_and_excluded_from_answer():
    """思考走 THINKING 回显、正文走 ASSISTANT_MESSAGE，两者不再混进同一个累加器。"""
    provider = _ScriptedProvider(
        [
            [ToolCall(name="list_x")],
            [
                TextDelta(delta="让我看看…", kind=TextKind.REASONING),
                TextDelta(delta="查到 2 个任务。"),
            ],
        ]
    )
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    assert [ev.text for ev in events if ev.eventType == EVENT_THINKING] == ["让我看看…"]
    assert [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE] == [
        "查到 2 个任务。"
    ]


def test_reasoning_does_not_enter_replayed_history():
    """思维链不得回灌给模型：回灌既污染后续轮次，又白烧 token。"""
    provider = _ScriptedProvider(
        [
            [
                TextDelta(delta="我先想想怎么查", kind=TextKind.REASONING),
                ToolCall(name="list_x"),
            ],
            [TextDelta(delta="done")],
        ]
    )
    agent = _Agent(provider=provider, tools=[_spec()])

    asyncio.run(_collect(agent))

    request = provider.calls[1]["history"][0]
    assert request["role"] == "assistant"
    assert request["content"] == "", "工具轮入历史的只能是正文，不含思维链"
    assert [c["name"] for c in request["tool_calls"]] == ["list_x"]


def test_call_draft_in_reasoning_is_never_flushed_to_client():
    """思维链里的调用草稿即便本轮工具调用**正常**，也不得外发（协议永不出现）。"""
    provider = _ScriptedProvider(
        [
            [ToolCall(name="list_x")],
            [
                TextDelta(
                    delta='正在调用：<invoke name="list_x"></invoke>', kind=TextKind.REASONING
                ),
                TextDelta(delta="查到 2 个任务。"),
            ],
        ]
    )
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    assert EVENT_THINKING not in _types(events), "含调用伪协议的思考须整段丢弃"
    assert [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE] == [
        "查到 2 个任务。"
    ]


def test_lone_reasoning_after_successful_tool_call_does_not_hard_fail():
    """已成功走过原生 FC 后，收尾轮只回思维链不算能力问题——安静结束，不误报。"""
    provider = _ScriptedProvider(
        [
            [ToolCall(name="list_x")],
            [TextDelta(delta="嗯，数据已经有了。", kind=TextKind.REASONING)],
        ]
    )
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(_collect(agent))

    # 不报错（能力没问题）、也不给答案（无正文），本轮整轮不外发
    assert EVENT_ERROR not in _types(events)
    assert EVENT_ASSISTANT_MESSAGE not in _types(events)
    assert EVENT_THINKING not in _types(events)
