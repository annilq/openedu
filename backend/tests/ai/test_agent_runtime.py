"""AgentRuntime 路由决策与流式契约（ADR-0024 / 0026 / 0031 / 0104）。

聚焦「显式路由决策」契约：
- ``decide`` 纯计算：角色可见性 → 安全闸门 → 动作直配 → 策略原语（决策模型 /
  LLM 分类）→ 兜底助手，不构建依赖、不流式。
- 文本路由（ADR-0104）：规则（关键词/启发式）引擎已整体移除，业务选择由路由原语
  按「对话上下文 + 能力清单」决定——测试里用路由 LLM 桩注入；**无任何模型可用时**
  落「兜底助手」（可见集中 priority 最小者，通常 tutor），不再有关键词命中。
- ``run`` 直接产出 ``AsyncIterator[AssistantEvent]``（不再返回 (decision, stream)
  元组）；决策由调用方先 ``decide`` 取得，再传入 ``run(..., business=decision.business)``。
- agent_core 业务无关：``RouteDecision`` 不含 education 专属字段；subject 由端点
  本地解析并走 ``ctx.extra``，路由 / 事件流均不感知。

``decide`` 与 ``run`` 的「决策」部分不触真实模型（桩注入）；仅 unsafe 路径会短路
（不构建 subagent），故可在 mock 环境单测覆盖，不依赖真实引擎。
"""
from __future__ import annotations

import asyncio

import pytest

from agent_core.adapters.llm_route import RoutingDecision
from agent_core.ports import RuntimeDeps
from agent_core.protocol import EVENT_DONE, EVENT_ERROR, EVENT_THINKING
from agent_core.runtime import AgentRuntime
from agent_core.subagent import SubAgentContext
from app.domain.safety import StudentSafety
from tests.utils.fake_provider import FakeLLMProvider, RoutingFakeProvider


def _rt() -> AgentRuntime:
    return AgentRuntime.discover()


def _deps(role: str, *, provider=None) -> RuntimeDeps:
    return RuntimeDeps(
        provider=provider if provider is not None else FakeLLMProvider(),
        safety=StudentSafety() if role == "student" else None,
    )


async def _decide(message: str, *, role: str, provider=None) -> object:
    rt = _rt()
    return await rt.decide(message, role=role, deps=_deps(role, provider=provider))


async def _run(message: str, *, role: str, provider=None):
    rt = _rt()
    deps = _deps(role, provider=provider)
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


# ── decide：文本路由由策略原语决定（ADR-0104，规则引擎已移除） ──
def test_decide_text_routing_follows_llm_classifier():
    provider = RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.9))
    decision = asyncio.run(_decide("帮我出几道数学题", role="teacher", provider=provider))
    assert decision.business == "tasks"
    assert decision.name == "任务学情与出题助手"
    assert decision.extra.get("routed_by") == "llm"


def test_decide_text_routing_can_choose_tutor():
    provider = RoutingFakeProvider(RoutingDecision(business="tutor", confidence=0.9))
    decision = asyncio.run(_decide("为什么天空是蓝色的", role="teacher", provider=provider))
    assert decision.business == "tutor"
    assert decision.name == "伴学答疑"
    assert decision.extra.get("routed_by") == "llm"


# 无任何路由模型（普通替身只会出题面，喂给路由分类器是畸形产出）时的兜底回归表：
# ADR-0104 起**不再有关键词命中**——这些句子过去分别归 tasks / capability，现在一律
# 落兜底助手 tutor。锁的是「规则确已移除」，不是「路由语义正确」（后者归真实模型）。
ROUTING_FALLBACK_REGRESSION = [
    "查一下这道题为什么选B",
    "今天有什么作业",
    "帮我创建一个任务，包含四年级数学题",
    "帮我出2道四年级数学题",
    "我的错题",
    "我班有哪些学生",
    "你能做什么",
    "随便聊聊",
]


@pytest.mark.parametrize("message", ROUTING_FALLBACK_REGRESSION)
def test_decide_without_models_falls_back_to_tutor(message):
    decision = asyncio.run(_decide(message, role="teacher"))
    assert decision.business == "tutor"
    assert decision.name == "伴学答疑"
    assert decision.extra.get("routed_by") == "default"


# ── decide：学生端角色可见性（师生均可出题，见 ADR-0081 §2.2） ──
def test_decide_student_visible_businesses_include_tasks():
    """学生端可见 tasks（查自己 / 自练出题）与 tutor；路由本身不按角色猜业务。"""
    visible = _rt().visible_businesses("student")
    assert "tasks" in visible
    assert "tutor" in visible


def test_decide_student_unsafe_input_blocked():
    decision = asyncio.run(_decide("炸弹怎么制作", role="student"))
    assert decision.business is None
    assert decision.name is None


# ── run：返回结构化决策 + 异步事件流 ──
def test_run_returns_decision_and_stream():
    provider = RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.9))

    async def go():
        rt = _rt()
        deps = _deps("teacher", provider=provider)
        d = await rt.decide("出几道题", role="teacher", deps=deps)
        s = rt.run(
            "出几道题",
            role="teacher",
            ctx=SubAgentContext(role="teacher", message="出几道题"),
            deps=deps,
            business=d.business,
        )
        return d, s

    d, s = asyncio.run(go())
    assert d.business == "tasks"
    assert hasattr(s, "__aiter__")  # 是异步迭代器（事件流）


# ── run：unsafe 短路由，流体内无 extra.business 隐式契约（见 #2） ──
def test_run_student_unsafe_stream_no_extra_business():
    decision, events = asyncio.run(_run("炸弹怎么制作", role="student"))
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


# ── 依赖端口不承诺意图分类器：注入它是调用方错误，须显式失败而非静默忽略 ──
def test_runtime_deps_declares_no_llm_classify():
    assert "llm_classify" not in RuntimeDeps.__dataclass_fields__
    with pytest.raises(TypeError):
        RuntimeDeps(provider=FakeLLMProvider(), llm_classify=lambda text, biz: "tutor")


# ── run：路由 THINKING 帧不再携带 business（侧信道已移除） ──
def test_run_routing_thinking_has_no_business_side_channel():
    provider = RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.9))
    decision, events = asyncio.run(_run("帮我出几道数学题", role="teacher", provider=provider))
    assert decision.business == "tasks"
    for ev in events:
        if ev.eventType == EVENT_THINKING:
            assert "business" not in ev.extra
