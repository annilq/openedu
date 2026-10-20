"""通用 LLM 分类路由：``decide`` 策略可切换（llm / decision / auto）。

主接缝 = ``AgentRuntime.decide`` 返回值（沿用 ai-intent-routing 测试缝）：只断言
「信号 + 角色 + history + deps + 策略 → 路由决策」，不碰内部级别。LLM 用内存桩，
无网络依赖。

覆盖（对应「新增普通 llm 分类功能，方便切换」）：
- ``AI_ROUTING_STRATEGY=llm`` → 按 LLM 返回业务路由（``routed_by == "llm"``）；
- provider 未配置 / 模型回传不可见业务 → 回落无命中引导（ADR-0104 规则已移除；ADR-0105 落 capability）；
- 策略切换：``auto``（默认）决策模型不可用即落到 LLM 分类，``decision`` 用决策模型，
  ``llm`` 只用 LLM 分类；
- 动作直配（ADR-0081）仍在所有策略原语之前。
"""
from __future__ import annotations

import asyncio
from contextlib import contextmanager

from agent_core import IntentSignal
from agent_core.adapters.llm_route import ROUTING_SYSTEM_PROMPT, RoutingDecision
from agent_core.ports import DecisionModel, DecisionResult, RuntimeDeps
from agent_core.runtime import AgentRuntime, get_routing_strategy, set_routing_strategy
from app.domain.safety import StudentSafety
from tests.utils.fake_provider import FakeLLMProvider, RoutingFakeProvider


class _StubDecisionModel(DecisionModel):
    """内存桩：返回预设 ``DecisionResult``。"""

    def __init__(self, result: DecisionResult | None = None, *, available: bool = True):
        self._result = result
        self._available = available

    def available(self) -> bool:
        return self._available

    async def decide(self, *, state: str, options):  # noqa: ANN001 — 测试桩
        return self._result


class _UnconfiguredProvider(FakeLLMProvider):
    """模拟「未配置引擎」的 provider：``configured`` 为 False。"""

    configured = False


@contextmanager
def _strategy(s: str | None):
    prev = get_routing_strategy()
    set_routing_strategy(s)
    try:
        yield
    finally:
        set_routing_strategy(prev if prev != s else None)
        set_routing_strategy(None)


def _rt() -> AgentRuntime:
    return AgentRuntime.discover()


def _deps(*, provider=None, dm=None, role: str = "teacher") -> RuntimeDeps:
    return RuntimeDeps(
        provider=provider if provider is not None else FakeLLMProvider(),
        safety=StudentSafety() if role == "student" else None,
        decision_model=dm,
    )


def _decide(
    message,
    *,
    role: str = "teacher",
    provider=None,
    dm=None,
    history=None,
    strategy: str | None = None,
) -> object:
    with _strategy(strategy):
        rt = _rt()
        return asyncio.run(
            rt.decide(
                message,
                role=role,
                deps=_deps(provider=provider, dm=dm, role=role),
                history=history,
            )
        )


# ── llm 策略：按 LLM 返回业务路由 ──
def test_llm_routing_routes_when_strategy_llm():
    provider = RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.9))
    d = _decide("帮我出一道题", provider=provider, strategy="llm")
    assert d.business == "tasks"
    assert d.extra.get("routed_by") == "llm"
    assert d.extra.get("confidence") == 0.9


# ── llm 策略：provider 未配置 → 回落无命中引导（capability） ──
def test_llm_routing_falls_back_when_provider_none():
    d = _decide("帮我出2道四年级数学题", provider=None, strategy="llm")
    assert d.business == "capability"  # 都没有命中 → 能力引导（规则已移除，ADR-0104/0105）
    assert d.extra.get("routed_by") == "default"


# ── llm 策略：provider 未配置（configured=False）→ 回落无命中引导（capability） ──
def test_llm_routing_falls_back_when_model_unconfigured():
    d = _decide("帮我出2道四年级数学题", provider=_UnconfiguredProvider(), strategy="llm")
    assert d.business == "capability"
    assert d.extra.get("routed_by") == "default"


# ── llm 策略：模型回传不可见业务 → 回落无命中引导 ──
def test_llm_routing_falls_back_when_invalid_business():
    provider = RoutingFakeProvider(
        RoutingDecision(business="nonexistent_biz", confidence=0.9)
    )
    d = _decide("随便一句", provider=provider, strategy="llm")
    assert d.business != "nonexistent_biz"
    assert d.business in _rt().visible_businesses("teacher")
    assert d.extra.get("routed_by") == "default"


# ── 默认 auto：决策模型不可用即落到 LLM 分类（规则兜底已移除） ──
def test_strategy_auto_falls_through_to_llm():
    provider = RoutingFakeProvider(
        RoutingDecision(business="tutor", confidence=0.99)
    )
    d = _decide("帮我出2道四年级数学题", provider=provider, strategy="auto")
    assert d.business == "tutor"  # LLM 分类说了算
    assert d.extra.get("routed_by") == "llm"


# ── 策略切换：decision vs llm 互不干扰 ──
def test_strategy_switch_decision_vs_llm():
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.9))
    provider = RoutingFakeProvider(RoutingDecision(business="tutor", confidence=0.9))

    d_dec = _decide("随便一句", provider=provider, dm=dm, strategy="decision")
    assert d_dec.business == "tasks"
    assert d_dec.extra.get("routed_by") == "decision"

    d_llm = _decide("随便一句", provider=provider, dm=dm, strategy="llm")
    assert d_llm.business == "tutor"
    assert d_llm.extra.get("routed_by") == "llm"


# ── 提示词快照：剥离 ADR-0104 已删除的硬编码编号规则（T04） ──
def test_routing_system_prompt_has_no_hardcoded_rules():
    """``ROUTING_SYSTEM_PROMPT`` 不得内嵌任何编号路由规则（ADR-0104 规则整体移除）。

    只允许：能力清单 + 上下文的角色说明 + 「只输出业务键」的格式约束。断言缺失的
    子串对应原提示词里 3 条编号规则（沿用上一轮 / 学生作答 / 只输出**某个业务键）。
    """
    assert "沿用上一轮" not in ROUTING_SYSTEM_PROMPT
    assert "学生作答" not in ROUTING_SYSTEM_PROMPT
    assert "判定规则" not in ROUTING_SYSTEM_PROMPT
    assert "只输出**某个业务键" not in ROUTING_SYSTEM_PROMPT
    # 格式约束（输出业务键）仍保留，但不得是带 markdown 加粗的编号规则形式。
    assert "只输出" in ROUTING_SYSTEM_PROMPT and "业务键" in ROUTING_SYSTEM_PROMPT


# ── 动作直配（ADR-0081）仍在所有策略原语之前 ──
def test_action_direct_match_prior_to_strategy_models():
    dm = _StubDecisionModel(DecisionResult(choice="tutor", prob=0.99))
    provider = RoutingFakeProvider(RoutingDecision(business="tutor", confidence=0.99))
    rt = _rt()
    d = asyncio.run(
        rt.decide(
            IntentSignal(text="", action="task_generate"),
            role="teacher",
            deps=_deps(provider=provider, dm=dm, role="teacher"),
        )
    )
    assert d.business == "tasks"  # 动作直配命中
    assert d.extra.get("routed_by") == "action"
