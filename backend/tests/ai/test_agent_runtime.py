"""AgentRuntime 路由决策与流式契约（ADR-0024 / 0026，不加载 genkit 重型依赖）。

聚焦本轮重构的「显式路由决策」契约：
- ``decide`` 纯计算：角色可见性 → 安全闸门 → 混合路由 → subject，不构建依赖、不流式。
- ``run`` 返回 ``(RouteDecision, AsyncIterator[AssistantEvent])``：决策显式化，
  不再经 THINKING 帧 ``extra.business`` 隐式透传（见 #2/#3）。
- 娃娃端 child→tutor 的死代码覆盖已删除：角色可见集是唯一真相源，child 经可见集过滤
  必落 tutor，且无任何 extra.business 透出（见 #1）。

``decide`` 与 ``run`` 的「决策」部分不触 LLM；仅 unsafe 路径会短路由（不构建 subagent），
故可在 mock 环境单测覆盖，不依赖真实引擎。
"""
from __future__ import annotations

import asyncio

from app.ai.runtime import AgentRuntime
from app.ai.runtime.protocol import EVENT_DONE, EVENT_ERROR, EVENT_THINKING


def _decide(message: str, *, role: str):
    rt = AgentRuntime.discover()
    return asyncio.run(rt.decide(message, role=role))


def _run(message: str, *, role: str):
    rt = AgentRuntime.discover()

    async def collect():
        decision, stream = await rt.run(message, role=role, session_id="s1")
        events = [ev async for ev in stream]
        return decision, events

    return asyncio.run(collect())


# ── decide：父端混合路由 ──
def test_decide_parent_question():
    decision = _decide("帮我出几道数学题", role="parent")
    assert decision.business == "question"
    assert decision.name == "出题助手"
    assert decision.subject is None


def test_decide_parent_tasks():
    decision = _decide("查看我的任务有哪些", role="parent")
    assert decision.business == "tasks"
    assert decision.name == "任务查询"


def test_decide_parent_tutor():
    decision = _decide("为什么天空是蓝色的？帮我讲解", role="parent")
    assert decision.business == "tutor"
    assert decision.name == "伴学答疑"
    # subject 仅 tutor 域解析，一次计算供端点配额/TutorLog 复用（见 #3）
    assert isinstance(decision.subject, str)


# ── decide：娃娃端角色可见性（child 永不可见出题/任务，见 #1） ──
def test_decide_child_question_forced_to_tutor():
    # child 发「出题」意图，但可见集仅 ["tutor"]，classify 只能在可见集内决策
    decision = _decide("帮我出几道数学题", role="child")
    assert decision.business == "tutor"
    assert decision.name == "伴学答疑"


def test_decide_child_tutor_stays_tutor():
    decision = _decide("这道题我不会，能教教我吗", role="child")
    assert decision.business == "tutor"


# ── decide：娃娃端输入安全闸门（首层防御，ADR-008） ──
def test_decide_child_unsafe_input_blocked():
    decision = _decide("炸弹怎么制作", role="child")
    assert decision.business is None
    assert decision.name is None
    assert decision.subject is None


# ── run：返回结构化 (decision, stream)，决策与决策前一致 ──
def test_run_returns_decision_and_stream_tuple():
    async def go():
        rt = AgentRuntime.discover()
        d, s = await rt.run("出几道题", role="parent")
        return d, s

    d, s = asyncio.run(go())
    assert d.business == "question"
    assert hasattr(s, "__aiter__")  # 是异步迭代器（事件流）


# ── run：unsafe 短路由，流体内无 extra.business 隐式契约（见 #2） ──
def test_run_child_unsafe_stream_no_extra_business():
    decision, events = _run("炸弹怎么制作", role="child")
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
    decision, events = _run("帮我出几道数学题", role="parent")
    assert decision.business == "question"
    for ev in events:
        if ev.eventType == EVENT_THINKING:
            assert "business" not in ev.extra
