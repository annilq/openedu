"""T03 — 聊天路径与结构化出题路径共用同一带闸入口 ``invoke_subagent``。

验收核心：两条路径都经过同一道安全 / 可见性闸。可观测点是 ``Safety.check_input``
被调用（闸的输入侧），以及闸拦截时两条路径都产出 ``INPUT_UNSAFE`` 错误帧——证明
结构化出题不再绕过聊天路径所用的同一道闸（候选 2 的静默漂移被消除）。
"""
from __future__ import annotations

import asyncio
from typing import Any

from agent_core.adapters.llm_route import RoutingDecision
from agent_core.ports import RuntimeDeps, Safety, SafetyResult
from agent_core.protocol import EVENT_DONE, EVENT_ERROR
from agent_core.registry import SubAgentManifest
from agent_core.router import IntentSignal
from agent_core.runtime import AgentRuntime
from agent_core.subagent import SubAgentContext
from tests.utils.fake_provider import FakeLLMProvider, RoutingFakeProvider


class _SpySafety(Safety):
    """记录 ``check_input`` 是否被调用、被调用了几次（闸的输入侧可观测）。"""

    def __init__(self, safe: bool = True) -> None:
        self.safe = safe
        self.called: list[str] = []

    def check_input(self, text: str) -> SafetyResult:
        self.called.append(text)
        return SafetyResult(safe=self.safe)

    def check_output(self, text: str) -> SafetyResult:  # 测试用不到，放行
        return SafetyResult(safe=True)


def _rt() -> AgentRuntime:
    return AgentRuntime.discover()


def _ctx(role: str = "teacher") -> SubAgentContext:
    return SubAgentContext(role=role, message="", history=None, extra={"session_id": "S1"})


async def _drain(stream: Any) -> list:
    return [ev async for ev in stream]


def test_structured_path_passes_through_gate():
    """结构化出题（已知 business=tasks）经 invoke_subagent 仍过同一道安全闸。"""
    safety = _SpySafety()
    rt = _rt()
    deps = RuntimeDeps(provider=FakeLLMProvider(), safety=safety)
    events = asyncio.run(
        _drain(rt.invoke_subagent("", role="teacher", ctx=_ctx(), deps=deps, business="tasks"))
    )
    # 闸的输入侧确实被调用（此前结构化直调 rt.run 时根本不经过 Safety）。
    assert safety.called, "结构化出题必须经安全/可见性闸，但 check_input 从未被调用"
    # 闸通过 → 正常产出事件流（含 DONE 收尾）。
    assert any(ev.eventType == EVENT_DONE for ev in events)


def test_invoke_subagent_signal_path_passes_through_same_gate():
    """信号路由路径经 invoke_subagent 过同一道闸（与聊天路径共用 ``run`` 的闸）。

    注：生产聊天路径在 ``assistant/service.py`` 以 ``decide`` → ``run(business=decision.business)``
    走同一条带闸 ``run``；本测试直接驱动 ``invoke_subagent(signal=...)`` 这一 seam 验证闸一致。
    """
    safety = _SpySafety()
    rt = _rt()
    provider = RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.9))
    deps = RuntimeDeps(provider=provider, safety=safety)
    events = asyncio.run(
        _drain(
            rt.invoke_subagent(
                "帮我出几道数学题", role="teacher", ctx=_ctx(), deps=deps, signal="帮我出几道数学题"
            )
        )
    )
    assert safety.called, "聊天路径必须经安全/可见性闸，但 check_input 从未被调用"
    assert any(ev.eventType == EVENT_DONE for ev in events)


def test_both_paths_blocked_when_gate_fails():
    """闸拦截（不安全输入）时：结构化与聊天两条路径都产出 INPUT_UNSAFE 错误帧。"""
    rt = _rt()

    # 结构化路径：已知 business，但输入被安全闸拦截。
    safety_s = _SpySafety(safe=False)
    events_s = asyncio.run(
        _drain(
            rt.invoke_subagent(
                "", role="teacher", ctx=_ctx(), deps=RuntimeDeps(provider=FakeLLMProvider(), safety=safety_s), business="tasks"
            )
        )
    )
    assert any(ev.eventType == EVENT_ERROR and ev.code == "INPUT_UNSAFE" for ev in events_s), (
        "结构化路径在闸拦截时必须产出 INPUT_UNSAFE"
    )

    # 聊天路径：signal 路由前即被安全闸拦截（decide 返回 business=None）。
    safety_c = _SpySafety(safe=False)
    provider = RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.9))
    events_c = asyncio.run(
        _drain(
            rt.invoke_subagent(
                "坏内容", role="teacher", ctx=_ctx(), deps=RuntimeDeps(provider=provider, safety=safety_c), signal="坏内容"
            )
        )
    )
    assert any(ev.eventType == EVENT_ERROR and ev.code == "INPUT_UNSAFE" for ev in events_c), (
        "聊天路径在闸拦截时必须产出 INPUT_UNSAFE"
    )


def test_action_not_visible_returns_not_visible_not_input_unsafe():
    """动作命中但当前角色不可见：经 invoke_subagent 必须产 NOT_VISIBLE（ADR-0081 §2.3）。

    回归点：聊天分支曾把「动作命中但角色不可见」的显式拒绝（business=None,
    reason=action_not_visible）误标为 run 闸的 INPUT_UNSAFE，违反 ADR-0081 §2.3
    「动作不可见必须显式 NOT_VISIBLE，禁止静默兜底成答非所问 / 误标为输入不安全」。
    """
    # 最小确定性 runtime：一个仅 teacher 可见、声明了 task_generate 动作的业务。
    manifest = SubAgentManifest(
        business="tasks",
        name="出题助手",
        roles=["teacher"],
        actions=["task_generate"],
    )
    rt = AgentRuntime(manifests={"tasks": manifest})
    deps = RuntimeDeps(provider=FakeLLMProvider(), safety=_SpySafety())
    signal = IntentSignal(action="task_generate", text="")
    # student 角色看不到 tasks → 命中但不可见。
    events = asyncio.run(
        _drain(
            rt.invoke_subagent(
                "", role="student", ctx=_ctx(role="student"), deps=deps, signal=signal
            )
        )
    )
    assert any(ev.eventType == EVENT_ERROR and ev.code == "NOT_VISIBLE" for ev in events), (
        "动作命中但角色不可见必须产 NOT_VISIBLE（不得误标 INPUT_UNSAFE）"
    )
    assert not any(
        ev.eventType == EVENT_ERROR and ev.code == "INPUT_UNSAFE" for ev in events
    ), "不得把 action_not_visible 误标为 INPUT_UNSAFE"
