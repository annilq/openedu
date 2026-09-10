"""BaseSubAgent 协议助手（方案B）测试：_tool 句柄保证 tool_call/tool_result 同名成对。

验证「tool_call 与 tool_result 共用同一 tool 名」这一深不变量确实被收口到基类，
而非由各 subagent 手搓字面量（删除 _tool 会在 3 个 subagent 重现同名/顺序风险）。
"""
from __future__ import annotations

import asyncio

from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
)
from agent_core.subagent import BaseSubAgent, SubAgentContext, ToolCallPair


class _FakeAgent(BaseSubAgent):
    """最小可运行 subagent，仅用于验证基类帧助手行为。"""

    business = "fake"

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        tc = self._tool("do_work", label="干活", args={"x": 1})
        yield tc.call
        result = await asyncio.sleep(0, result={"ok": True})
        yield tc.result(result)
        yield self._finish("done", blocked=False)


async def _collect(agen):
    return [f async for f in agen]


def test_tool_handle_exposes_call_with_name_label_args():
    ag = _FakeAgent(provider=object())
    tc = ag._tool("do_work", label="干活", args={"x": 1})
    assert isinstance(tc, ToolCallPair)
    assert tc.name == "do_work"
    assert tc.call.eventType == EVENT_TOOL_CALL
    assert tc.call.tool == "do_work"
    assert tc.call.label == "干活"
    assert tc.call.args == {"x": 1}


def test_tool_result_share_same_name():
    ag = _FakeAgent(provider=object())
    tc = ag._tool("do_work")
    res = tc.result({"ok": True})
    assert res.eventType == EVENT_TOOL_RESULT
    # 关键不变量：result 的 tool 名必须等于 call 的 tool 名（单一来源）
    assert res.tool == tc.call.tool == tc.name == "do_work"
    assert res.result == {"ok": True}


def test_tool_frames_ordered_and_named_in_stream():
    ag = _FakeAgent(provider=object())
    frames = asyncio.run(_collect(ag.run("hi", SubAgentContext())))

    calls = [f for f in frames if f.eventType == EVENT_TOOL_CALL]
    results = [f for f in frames if f.eventType == EVENT_TOOL_RESULT]
    assert len(calls) == 1 and len(results) == 1
    assert calls[0].tool == results[0].tool == "do_work"
    # 顺序：TOOL_CALL 必在 TOOL_RESULT 之前
    assert frames.index(calls[0]) < frames.index(results[0])


def test_finish_is_assistant_message_with_blocked_flag():
    ag = _FakeAgent(provider=object())
    f = ag._finish("done", blocked=True)
    assert f.eventType == EVENT_ASSISTANT_MESSAGE
    assert f.text == "done"
    assert f.blocked is True
