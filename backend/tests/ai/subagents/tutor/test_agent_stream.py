"""T02 — TutorSubAgent 不得伪造 ``tutor_explain`` 工具帧（候选 1）。

钉死两件事：
- ``run`` 产出的事件流里**不再出现** `tutor_explain` 这个 TOOL_CALL / TOOL_RESULT 帧
  （它从未注册 ToolSpec、不进真实 tool loop，是误导性的「戏服」）。
- 真活不受影响：仍下发音视频讲解 delta（ASSISTANT_MESSAGE）、交互演示 DATA 帧
  （``interactive_scene``）、溯源 DATA 帧（``rag_sources``）。

本仓库未启用 ``pytest-asyncio``，异步入口统一用 ``asyncio.run`` 包裹（见
``tests/ai/subagents/tutor/test_scene_intent.py`` 先例）。
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass

from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
)
from agent_core.subagent import SubAgentContext
from app.ai.subagents.tutor.agent import TutorSubAgent
from app.domain.tutor import RAGSource


@dataclass
class _FakeChunk:
    """模仿 ``TutorStreamChunk`` 的极简替身（只暴露 run 用到的字段）。"""

    sources: list | None = None
    delta: str | None = None
    done: bool = False
    answer: str | None = None
    blocked: bool = False
    reason: str | None = None


class _FakeProvider:
    """不接真模型的 provider 替身（run 路径下 aexplain_stream 被直接替换，不触真 LLM）。"""

    configured = True


async def _fake_scene(*_args, **_kwargs) -> dict:
    """确定性交互演示：返回合法场景卡（真实三层识别链路由 test_scene_intent 覆盖）。"""
    return {"kind": "reflection", "figure": {"key": "square", "label": "正方形"}}


def _fake_explain_stream():
    """确定性讲解流：先溯源、再两段正文增量、最后收尾（正常流，未拦截）。"""

    async def _gen():
        yield _FakeChunk(
            sources=[
                RAGSource(
                    material_id="m1",
                    material_name="教材P12",
                    chunk_id="c1",
                    snippet="轴对称是关于一条直线对折后重合。",
                )
            ]
        )
        yield _FakeChunk(delta="轴对称")
        yield _FakeChunk(delta="就是沿对称轴对折。")
        yield _FakeChunk(done=True, answer="轴对称就是沿对称轴对折。", blocked=False)

    return _gen()


def _collect(agent: TutorSubAgent, ctx: SubAgentContext) -> list:
    frames = []

    async def _run():
        async for ev in agent.run("什么是轴对称", ctx, session=None):
            frames.append(ev)

    asyncio.run(_run())
    return frames


def _make_agent() -> TutorSubAgent:
    agent = TutorSubAgent(provider=_FakeProvider())
    # 把真 LLM/KB 流替换为确定性替身；场景解析同理（其链路由 test_scene_intent 覆盖）。
    agent.service.aexplain_stream = lambda **_: _fake_explain_stream()  # type: ignore[assignment]
    agent._interactive_scene_for = _fake_scene  # type: ignore[assignment]
    return agent


def test_tutor_stream_has_no_fake_tutor_explain_tool_frame():
    """流中既无 `tutor_explain` TOOL_CALL，也无 `tutor_explain` TOOL_RESULT。"""
    agent = _make_agent()
    ctx = SubAgentContext(
        role="student", message="什么是轴对称", history=[], model=None, skills="", extra={}
    )
    frames = _collect(agent, ctx)

    tool_frames = [
        f
        for f in frames
        if f.eventType in (EVENT_TOOL_CALL, EVENT_TOOL_RESULT)
        and getattr(f, "tool", None) == "tutor_explain"
    ]
    assert tool_frames == [], "tutor_explain 不应再以 TOOL_CALL/RESULT 帧出现"


def test_tutor_stream_keeps_real_work_explain_scene_sources():
    """删除伪帧后，讲解 delta + 交互演示 + 溯源三类真活帧仍在。"""
    agent = _make_agent()
    ctx = SubAgentContext(
        role="student", message="什么是轴对称", history=[], model=None, skills="", extra={}
    )
    frames = _collect(agent, ctx)

    # 讲解 delta：至少一条非空 ASSISTANT_MESSAGE
    explain_deltas = [
        f
        for f in frames
        if f.eventType == EVENT_ASSISTANT_MESSAGE and (f.text or f.delta)
    ]
    assert explain_deltas, "应仍下发音视频讲解 delta（ASSISTANT_MESSAGE）"

    # 交互演示 DATA 帧
    scene_frames = [
        f
        for f in frames
        if f.eventType == EVENT_DATA and (f.extra or {}).get("type") == "interactive_scene"
    ]
    assert scene_frames, "应仍下发 interactive_scene DATA 帧"

    # 溯源 DATA 帧
    source_frames = [
        f
        for f in frames
        if f.eventType == EVENT_DATA and (f.extra or {}).get("type") == "rag_sources"
    ]
    assert source_frames, "应仍下发 rag_sources DATA 帧"
