"""流式 tool loop 测试（ADR-0097）：``ToolSpec.stream_handler`` 分支的五条契约。

1. 中间帧（THINKING / DATA / STEP）按序外发，ToolOutcome.data 成为回灌 content；
2. 流式中途抛异常：已发帧保留（部分事实不可收回），补 tool_result 关闭配对，
   按 ``{"error": ...}`` 回灌，**不**硬失败；
3. generator 正常结束却未 yield ToolOutcome：协议违例 → error 回灌（空 content 会让
   模型以为工具什么都没返回）；
4. 流式分支**不**调 SubAgent.render_tool_result（展示帧由 generator 自负，防同卡两发）；
5. 同步路径行为不变（render_tool_result 照常、回灌照旧）。

替身：``FakeLLMProvider`` 脚本化工具调用（默认单跳后收尾）。
"""
from __future__ import annotations

import asyncio
from typing import Any, AsyncIterator

from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_STEP,
    EVENT_THINKING,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
)
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools
from agent_core.tools import ToolOutcome, ToolSpec
from tests.utils.fake_provider import FakeLLMProvider


async def _ok_stream(args: dict, *, ctx: SubAgentContext, session: Any = None) -> AsyncIterator[Any]:
    """正常流式工具：STEP → THINKING → DATA → ToolOutcome。"""
    yield _step("正在生成")
    yield _thinking("想一下")
    yield _data({"q": "1+1"})
    yield ToolOutcome({"count": 1})


async def _boom_stream(args: dict, *, ctx: SubAgentContext, session: Any = None) -> AsyncIterator[Any]:
    yield _data({"partial": True})
    raise RuntimeError("流中断")


async def _no_outcome_stream(args: dict, *, ctx: SubAgentContext, session: Any = None) -> AsyncIterator[Any]:
    yield _thinking("只有思考")
    # 协议违例：正常结束但没有 ToolOutcome


def _step(label: str):
    from agent_core.protocol import step

    return step(label)


def _thinking(delta: str):
    from agent_core.protocol import thinking

    return thinking(delta)


def _data(payload: dict):
    from agent_core.protocol import data_event

    return data_event(payload, extra={"type": "question"})


class _StreamAgent(BaseSubAgent):
    business = "streamfake"

    # 记录 render_tool_result 被调用的次数（流式分支应为 0）。
    render_calls: list[str] = []

    async def run(self, message: str, ctx: SubAgentContext, *, session: Any = None) -> AsyncIterator[Any]:
        # tools 恒非空，runtime 不会走到这里；仅为满足抽象契约。
        yield _thinking("unused")

    def __init__(self, *, stream: bool = True, boom: bool = False, no_outcome: bool = False):
        super().__init__(provider=FakeLLMProvider())
        if boom:
            sh = _boom_stream
        elif no_outcome:
            sh = _no_outcome_stream
        else:
            sh = _ok_stream
        self.tools = [
            ToolSpec(
                name="gen",
                description="流式生成",
                schema={"type": "object", "properties": {}, "required": []},
                stream_handler=sh if stream else None,
                handler=(lambda args, *, ctx, session=None: asyncio.sleep(0, result={"sync": True})) if not stream else None,
            )
        ]
        self.render_calls = []

    def render_tool_result(self, name: str, result: Any) -> list[Any]:
        self.render_calls.append(name)
        return [_data({"rendered": name})]


class _SyncAgent(_StreamAgent):
    def __init__(self):
        super().__init__(stream=False)


async def _drive(agent: BaseSubAgent) -> list[Any]:
    return [ev async for ev in run_with_tools(agent, "出题", SubAgentContext())]


def test_stream_tool_frames_and_outcome_backfeed():
    agent = _StreamAgent()
    frames = asyncio.run(_drive(agent))

    kinds = [f.eventType for f in frames]
    # 顺序：TOOL_CALL → STEP → THINKING → DATA → TOOL_RESULT → ASSISTANT_MESSAGE
    assert kinds == [
        EVENT_TOOL_CALL,
        EVENT_STEP,
        EVENT_THINKING,
        EVENT_DATA,
        EVENT_TOOL_RESULT,
        EVENT_ASSISTANT_MESSAGE,
    ], kinds
    tr = frames[4]
    assert tr.result == {"count": 1}, "ToolOutcome.data 即回灌/展示的 tool_result 载荷"
    # 流式分支不调 render_tool_result（防同卡两发）
    assert agent.render_calls == []


def test_stream_tool_exception_keeps_partial_frames_and_closes_pair():
    agent = _StreamAgent(boom=True)
    frames = asyncio.run(_drive(agent))

    kinds = [f.eventType for f in frames]
    assert kinds[0] == EVENT_TOOL_CALL
    # 异常前已发的 DATA 帧保留（部分事实不可收回）
    assert EVENT_DATA in kinds, "已发帧必须保留"
    # 配对关闭：仍补 TOOL_RESULT，载荷为 error
    tr = next(f for f in frames if f.eventType == EVENT_TOOL_RESULT)
    assert "流中断" in str(tr.result)
    # 不硬失败：收尾轮照常产出正文（模型看到 error 回灌自行决定）
    assert EVENT_ASSISTANT_MESSAGE in kinds


def test_stream_tool_without_outcome_is_protocol_violation():
    agent = _StreamAgent(no_outcome=True)
    frames = asyncio.run(_drive(agent))

    tr = next(f for f in frames if f.eventType == EVENT_TOOL_RESULT)
    assert "ToolOutcome" in str(tr.result), "未以 ToolOutcome 收尾 → error 回灌"


def test_sync_tool_path_unchanged():
    agent = _SyncAgent()
    frames = asyncio.run(_drive(agent))

    kinds = [f.eventType for f in frames]
    assert kinds == [
        EVENT_TOOL_CALL,
        EVENT_TOOL_RESULT,
        EVENT_DATA,  # render_tool_result 照常被调用
        EVENT_ASSISTANT_MESSAGE,
    ], kinds
    assert agent.render_calls == ["gen"]
    assert frames[1].result == {"sync": True}
