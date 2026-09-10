"""``FakeLLMProvider`` 工具脚本契约测试（ADR-0033 第 6 阶段）。

替身本身也是被测对象：它的失真会以「实现看起来有问题」的形式把红点引到生产代码上。
这里钉死三件事：

1. **默认单跳**：不传脚本时仍是「首跳请求下发列表第一个工具，回灌后收尾」——既有
   用例依赖此行为，改它等于制造无声回归。
2. **显式多跳**：脚本按跳序取用，用完收尾；``calls`` 忠实记录实际发出的调用。
3. **跳数只认工具结果**：``role == "tool"`` 才算跑完一跳。客户端自带历史（全是
   user/assistant 轮次）**不得**吃掉首轮工具调用——旧实现用 ``if history`` 一刀切，
   会让 ``/assistant/chat`` 的 ``history`` 字段把查询静默降级成纯聊天。
"""
from __future__ import annotations

import asyncio
from typing import Any

from agent_core.ports import TextDelta, ToolCall
from tests.utils.fake_provider import FakeLLMProvider, _completed_hops

_TOOLS = [
    {"name": "list_children"},
    {"name": "list_parent_tasks"},
    {"name": "list_wrong_questions"},
]


def _collect(provider: FakeLLMProvider, *, history: list[dict] | None = None) -> list[Any]:
    async def _go() -> list[Any]:
        return [ev async for ev in provider.stream("sys", "usr", tools=_TOOLS, history=history)]

    return asyncio.run(_go())


def _tool_result(name: str) -> dict:
    return {"role": "tool", "name": name, "ref": "call_0", "content": "{}"}


def test_default_script_is_single_hop_then_wrapup():
    provider = FakeLLMProvider()
    first = _collect(provider)
    assert len(first) == 1 and isinstance(first[0], ToolCall)
    assert (first[0].name, first[0].args) == ("list_children", {})  # 下发列表第一个
    assert provider.calls == [("list_children", {})]

    second = _collect(provider, history=[_tool_result("list_children")])
    assert len(second) == 1 and isinstance(second[0], TextDelta)
    assert second[0].delta == provider.tool_text
    assert provider.calls == [("list_children", {})]  # 收尾轮不再发工具
    assert provider.requests == 2


def test_explicit_script_walks_hops_in_order_then_stops():
    provider = FakeLLMProvider().script("list_children", ("list_wrong_questions", {"child_id": "c1"}))
    assert provider._next_step(0, _TOOLS) == ("list_children", {})
    assert provider._next_step(1, _TOOLS) == ("list_wrong_questions", {"child_id": "c1"})
    assert provider._next_step(2, _TOOLS) is None  # 脚本用完 → 收尾

    first = _collect(provider)
    assert isinstance(first[0], ToolCall) and first[0].args == {}
    second = _collect(provider, history=[_tool_result("list_children")])
    assert isinstance(second[0], ToolCall)
    assert (second[0].name, second[0].args) == ("list_wrong_questions", {"child_id": "c1"})
    third = _collect(
        provider, history=[_tool_result("list_children"), _tool_result("list_wrong_questions")]
    )
    assert isinstance(third[0], TextDelta)
    assert provider.calls == [("list_children", {}), ("list_wrong_questions", {"child_id": "c1"})]
    assert provider.requests == 3


def test_client_supplied_history_does_not_swallow_first_tool_call():
    """回归：``history`` 非空但无工具结果 → 仍是首跳，必须发工具调用。"""
    provider = FakeLLMProvider()
    events = _collect(
        provider,
        history=[
            {"role": "user", "content": "你好"},
            {"role": "assistant", "content": "你好，有什么可以帮你？"},
        ],
    )
    assert len(events) == 1 and isinstance(events[0], ToolCall)
    assert events[0].name == "list_children"


def test_hop_counting_only_counts_tool_results():
    assert _completed_hops(None) == 0
    assert _completed_hops([]) == 0
    assert _completed_hops([{"role": "user", "content": "x"}]) == 0
    assert _completed_hops([_tool_result("a"), {"role": "assistant", "content": "y"}]) == 1


def test_script_and_reset_clear_counters():
    provider = FakeLLMProvider(tool_script=["list_children"])
    _collect(provider)
    assert provider.requests == 1
    provider.script("list_parent_tasks")
    assert provider.requests == 0 and provider.calls == []
    assert provider._next_step(0, _TOOLS) == ("list_parent_tasks", {})
