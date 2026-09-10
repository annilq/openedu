"""AgentRuntime 路由决策与流式契约（ADR-0024 / 0026 / 0031，不加载 genkit 重型依赖）。

聚焦本轮重构的「显式路由决策」契约：
- ``decide`` 纯计算：角色可见性 → 安全闸门 → 混合路由，不构建依赖、不流式。
- ``run`` 直接产出 ``AsyncIterator[AssistantEvent]``（不再返回 (decision, stream) 元组）；
  决策由调用方先 ``decide`` 取得，再传入 ``run(..., business=decision.business)``。
- agent_core 业务无关：``RouteDecision`` 不再含 education 专属的 ``subject`` 字段；
  subject 由端点本地解析并走 ``ctx.extra``，路由 / 事件流均不感知。

``decide`` 与 ``run`` 的「决策」部分不触 LLM；仅 unsafe 路径会短路（不构建 subagent），
故可在 mock 环境单测覆盖，不依赖真实引擎。
"""
from __future__ import annotations

import asyncio

from agent_core.ports import RuntimeDeps
from agent_core.protocol import EVENT_DONE, EVENT_ERROR, EVENT_THINKING
from agent_core.runtime import AgentRuntime
from agent_core.subagent import SubAgentContext
from app.domain.safety import ChildSafety
from tests.utils.fake_provider import FakeLLMProvider


def _rt() -> AgentRuntime:
    return AgentRuntime.discover()


def _deps(role: str) -> RuntimeDeps:
    return RuntimeDeps(
        provider=FakeLLMProvider(),
        safety=ChildSafety() if role == "child" else None,
    )


async def _decide(message: str, *, role: str) -> object:
    rt = _rt()
    return await rt.decide(message, role=role, deps=_deps(role))


async def _run(message: str, *, role: str):
    rt = _rt()
    deps = _deps(role)
    decision = await rt.decide(message, role=role, deps=deps)
    events = [
        ev
        async for ev in rt.run(
            message,
            role=role,
            ctx=SubAgentContext(role=role, message=message),
            deps=deps,
            business=decision.business,
        )
    ]
    return decision, events


# ── decide：父端混合路由 ──
def test_decide_parent_question():
    decision = asyncio.run(_decide("帮我出几道数学题", role="parent"))
    assert decision.business == "question"
    assert decision.name == "出题助手"


def test_decide_parent_query():
    decision = asyncio.run(_decide("查看我的任务有哪些", role="parent"))
    assert decision.business == "query"
    assert decision.name == "学情查询"


def test_decide_parent_tutor():
    decision = asyncio.run(_decide("为什么天空是蓝色的？帮我讲解", role="parent"))
    assert decision.business == "tutor"
    assert decision.name == "伴学答疑"


# ── decide：娃娃端角色可见性（child 永不可见出题；查询恒限自己，见 #1） ──
def test_decide_child_question_forced_to_tutor():
    decision = asyncio.run(_decide("帮我出几道数学题", role="child"))
    assert decision.business == "tutor"
    assert decision.name == "伴学答疑"


def test_decide_child_query_visible():
    """ADR-0033 放宽 ADR-0026：娃娃端可见 query，但工具侧恒查自己、去答案。"""
    decision = asyncio.run(_decide("今天有什么作业", role="child"))
    assert decision.business == "query"
    assert decision.name == "学情查询"


def test_decide_child_tutor_stays_tutor():
    decision = asyncio.run(_decide("这道题我不会，能教教我吗", role="child"))
    assert decision.business == "tutor"


# ── decide：娃娃端输入安全闸门（首层防御，ADR-008） ──
def test_decide_child_unsafe_input_blocked():
    decision = asyncio.run(_decide("炸弹怎么制作", role="child"))
    assert decision.business is None
    assert decision.name is None


# ── run：返回结构化决策 + 异步事件流 ──
def test_run_returns_decision_and_stream():
    async def go():
        rt = _rt()
        deps = _deps("parent")
        d = await rt.decide("出几道题", role="parent", deps=deps)
        s = rt.run(
            "出几道题",
            role="parent",
            ctx=SubAgentContext(role="parent", message="出几道题"),
            deps=deps,
            business=d.business,
        )
        return d, s

    d, s = asyncio.run(go())
    assert d.business == "question"
    assert hasattr(s, "__aiter__")  # 是异步迭代器（事件流）


# ── run：unsafe 短路由，流体内无 extra.business 隐式契约（见 #2） ──
def test_run_child_unsafe_stream_no_extra_business():
    decision, events = asyncio.run(_run("炸弹怎么制作", role="child"))
    assert decision.business is None
    # 流以 ERROR(INPUT_UNSAFE) + DONE 收尾，不路由到任何 subagent
    types = [ev.eventType for ev in events]
    assert EVENT_ERROR in types
    assert EVENT_DONE in types
    # 关键：没有任何帧经 extra.business 透出路由决策（消除端点隐式契约）
    for ev in events:
        assert "business" not in ev.extra, "路由决策不应再经 extra.business 隐式透传"
    # INPUT_UNSAFE 错误码存在
    assert any(ev.code == "INPUT_UNSAFE" for ev in events if ev.eventType == EVENT_ERROR)


# ── run：路由 THINKING 帧不再携带 business（侧信道已移除） ──
def test_run_routing_thinking_has_no_business_side_channel():
    decision, events = asyncio.run(_run("帮我出几道数学题", role="parent"))
    assert decision.business == "question"
    for ev in events:
        if ev.eventType == EVENT_THINKING:
            assert "business" not in ev.extra
