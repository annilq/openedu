"""通用 LLM 分类路由：``decide`` 策略可切换（rule / llm / decision / auto）。

主接缝 = ``AgentRuntime.decide`` 返回值（沿用 ai-intent-routing 测试缝）：只断言
「信号 + 角色 + history + deps + 策略 → 路由决策」，不碰内部级别。LLM 用内存桩，
无网络依赖。

覆盖（对应「新增普通 llm 分类功能，方便切换」）：
- ``AI_ROUTING_STRATEGY=llm`` → 按 LLM 返回业务路由（``routed_by == "llm"``）；
- provider 未配置 / 模型回传不可见业务 → 回落规则 ``classify``；
- 策略切换：``auto``（默认）不启用 LLM（decision→rule），``decision`` 用决策模型，
  ``llm`` 用 LLM 分类，``rule`` 忽略任何模型；
- 动作直配（ADR-0081）仍在所有策略原语之前。
"""
from __future__ import annotations

import asyncio
from contextlib import contextmanager

from agent_core import IntentSignal
from agent_core.adapters.llm_route import RoutingDecision
from agent_core.ports import DecisionModel, DecisionResult, RuntimeDeps
from agent_core.runtime import AgentRuntime, get_routing_strategy, set_routing_strategy
from app.domain.safety import StudentSafety
from tests.utils.fake_provider import FakeLLMProvider, StructuredDone


class _StubDecisionModel(DecisionModel):
    """内存桩：返回预设 ``DecisionResult``。"""

    def __init__(self, result: DecisionResult | None = None, *, available: bool = True):
        self._result = result
        self._available = available

    def available(self) -> bool:
        return self._available

    async def decide(self, *, state: str, options):  # noqa: ANN001 — 测试桩
        return self._result


class _RoutingFakeProvider(FakeLLMProvider):
    """路由 LLM 桩：当 schema 为 ``RoutingDecision`` 时回传预设决策。"""

    def __init__(self, decision: "RoutingDecision | None"):
        super().__init__()
        self._decision = decision

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if schema is RoutingDecision:
            if self._decision is not None:
                yield StructuredDone(data=self._decision)
            return
        async for ev in super().stream(
            system, prompt, schema=schema, tools=tools, history=history
        ):
            yield ev


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
    provider = _RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.9))
    d = _decide("帮我出一道题", provider=provider, strategy="llm")
    assert d.business == "tasks"
    assert d.extra.get("routed_by") == "llm"
    assert d.extra.get("confidence") == 0.9


# ── llm 策略：provider 未配置 → 回落规则 ──
def test_llm_routing_falls_back_when_provider_none():
    d = _decide("帮我出2道四年级数学题", provider=None, strategy="llm")
    assert d.business == "tasks"  # ADR-0101 正则命中
    assert d.extra.get("routed_by") != "llm"


# ── llm 策略：provider 未配置（configured=False）→ 回落规则 ──
def test_llm_routing_falls_back_when_model_unconfigured():
    d = _decide("帮我出2道四年级数学题", provider=_UnconfiguredProvider(), strategy="llm")
    assert d.business == "tasks"
    assert d.extra.get("routed_by") != "llm"


# ── llm 策略：模型回传不可见业务 → 回落规则 ──
def test_llm_routing_falls_back_when_invalid_business():
    provider = _RoutingFakeProvider(
        RoutingDecision(business="nonexistent_biz", confidence=0.9)
    )
    d = _decide("随便一句", provider=provider, strategy="llm")
    assert d.business != "nonexistent_biz"
    assert d.business in _rt().visible_businesses("teacher")
    assert d.extra.get("routed_by") != "llm"


# ── 默认 auto 不启用 LLM（即便 provider 可用），保持确定性 ──
def test_strategy_auto_does_not_use_llm_by_default():
    provider = _RoutingFakeProvider(
        RoutingDecision(business="tutor", confidence=0.99)
    )
    d = _decide("帮我出2道四年级数学题", provider=provider, strategy="auto")
    assert d.business == "tasks"  # 规则命中 tasks
    assert d.extra.get("routed_by") != "llm"


# ── 策略切换：decision vs llm 互不干扰 ──
def test_strategy_switch_decision_vs_llm():
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.9))
    provider = _RoutingFakeProvider(RoutingDecision(business="tutor", confidence=0.9))

    d_dec = _decide("随便一句", provider=provider, dm=dm, strategy="decision")
    assert d_dec.business == "tasks"
    assert d_dec.extra.get("routed_by") == "decision"

    d_llm = _decide("随便一句", provider=provider, dm=dm, strategy="llm")
    assert d_llm.business == "tutor"
    assert d_llm.extra.get("routed_by") == "llm"


# ── rule 策略：忽略任何模型，纯规则 ──
def test_rule_strategy_ignores_models():
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.9))
    provider = _RoutingFakeProvider(RoutingDecision(business="tutor", confidence=0.9))
    d = _decide("帮我出2道四年级数学题", provider=provider, dm=dm, strategy="rule")
    assert d.business == "tasks"  # 规则正则命中
    assert d.extra.get("routed_by") not in ("llm", "decision")


# ── 动作直配（ADR-0081）仍在所有策略原语之前 ──
def test_action_direct_match_prior_to_strategy_models():
    dm = _StubDecisionModel(DecisionResult(choice="tutor", prob=0.99))
    provider = _RoutingFakeProvider(RoutingDecision(business="tutor", confidence=0.99))
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
