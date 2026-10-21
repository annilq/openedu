"""路由采纳门控（ADR-0107，ticket 13）：``decide`` 接缝的回归。

主接缝 = ``AgentRuntime.decide`` 的返回值（沿用 ai-intent-routing 测试缝）：只断言
「信号 + 角色 + deps + 策略 → 路由决策」，不断言内部走了哪一级、比较了第几个阈值。

门控上移前的形状：``LayaDecisionModel(threshold=0.5)`` 在适配器内部做比较，低分被吞成
``None``——「模型没回」与「回了但 0.43」不可区分，runtime 无从按角色 / 按业务调整。
上移后：

- 决策模型**只出分数**（低分也如实回传，见 ``test_laya_adapter.py``）；
- runtime 拿 ``分数 >= min_adopt_score(业务, 角色)`` 决定是否采纳，取值序为
  **业务自述（manifest.min_adopt_score）→ 角色覆盖 → 全局默认 0.5**；
- LLM 分类的 ``confidence`` 走同一张表（此前完全不参与判断）；``None``（未自报）除外；
- 被否掉的候选随 ``extra["rejected"]`` 回传（此前轨迹上分不出「没命中」的两种成因）。

**阈值取值本身不进断言**：具体数字来自实测（ticket 12/13 的 eval 数据），会随文案与
权重漂移；这里只守「门控被应用了」这个行为。
"""
from __future__ import annotations

import asyncio
from contextlib import contextmanager
from dataclasses import replace

from agent_core.adapters.llm_route import RoutingDecision
from agent_core.ports import DecisionModel, DecisionResult, RuntimeDeps
from agent_core.registry import SubAgentManifest
from agent_core.runtime import (
    DEFAULT_MIN_ADOPT_SCORE,
    AgentRuntime,
    set_role_min_adopt_score,
    set_routing_strategy,
)
from tests.utils.fake_provider import RoutingFakeProvider


class _StubDecisionModel(DecisionModel):
    """内存桩：返回预设 ``DecisionResult``（分数由用例给定，桩不做任何门控）。"""

    def __init__(self, result: DecisionResult | None = None, *, available: bool = True):
        self._result = result
        self._available = available
        self.calls = 0

    def available(self) -> bool:
        return self._available

    async def decide(self, *, state: str, options):  # noqa: ANN001 — 测试桩
        self.calls += 1
        return self._result


class _CountingRoutingProvider(RoutingFakeProvider):
    """可观测的路由桩：数出「LLM 分类器被调用了几次」（交叉校验的代价据此断言）。"""

    def __init__(self, decision):
        super().__init__(decision)
        self.routing_calls = 0

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if schema is RoutingDecision:
            self.routing_calls += 1
        async for ev in super().stream(
            system, prompt, schema=schema, tools=tools, history=history
        ):
            yield ev


@contextmanager
def _strategy(s: str):
    """临时切换路由策略（退出即复位为环境变量值）。"""
    set_routing_strategy(s)
    try:
        yield
    finally:
        set_routing_strategy(None)


@contextmanager
def _role_score(role: str, score: float | None):
    """临时设置某角色的采纳门槛覆盖（退出即清除）。"""
    set_role_min_adopt_score(role, score)
    try:
        yield
    finally:
        set_role_min_adopt_score(role, None)


def _rt() -> AgentRuntime:
    return AgentRuntime.discover()


def _decide(
    message: str = "随便一句",
    *,
    role: str = "teacher",
    dm: DecisionModel | None = None,
    provider=None,
    strategy: str = "decision",
    rt: AgentRuntime | None = None,
):
    runtime = rt or _rt()
    deps = RuntimeDeps(provider=provider or RoutingFakeProvider(None), decision_model=dm)
    with _strategy(strategy):
        return asyncio.run(runtime.decide(message, role=role, deps=deps))


# ── 门控通过：分数够 → 采纳，并把门槛记进 extra ──
def test_adopt_when_score_meets_default_gate():
    dm = _StubDecisionModel(DecisionResult(choice="tutor", prob=0.9))
    d = _decide(dm=dm)
    assert d.business == "tutor"
    assert d.extra["routed_by"] == "decision"
    assert d.extra["min_adopt_score"] == DEFAULT_MIN_ADOPT_SCORE


# ── 门控不通过：低分不再静默消失，而是落到无命中引导，且轨迹可见 ──
def test_low_score_falls_to_guide_and_is_observable():
    """「回了但只有 0.2」与「模型没回」此前都是 ``None``，轨迹上分不出（ADR-0107）。"""
    dm = _StubDecisionModel(DecisionResult(choice="tutor", prob=0.2))
    d = _decide(dm=dm)
    assert d.business == "capability"  # 无命中引导（ADR-0105）
    assert d.extra["routed_by"] == "default"
    rejected = d.extra.get("rejected") or []
    assert rejected and rejected[0]["primitive"] == "decision"
    assert rejected[0]["business"] == "tutor"
    assert rejected[0]["score"] == 0.2
    assert rejected[0]["min_adopt_score"] == DEFAULT_MIN_ADOPT_SCORE


def test_no_answer_has_empty_rejected():
    """模型压根没回（``None``）→ 也落引导，但 ``rejected`` 为空：不是被门控否掉的。"""
    dm = _StubDecisionModel(None)
    d = _decide(dm=dm)
    assert d.business == "capability"
    assert not d.extra.get("rejected")


# ── 角色覆盖：同一分数，学生端被挡、教师端被采纳 ──
def test_role_override_blocks_student_but_not_teacher():
    """角色覆盖**机制**就位（生产当前不设值，理由是实测不支持，见 ADR-0107）。"""
    with _role_score("student", 0.8):
        d_student = _decide(role="student", dm=_StubDecisionModel(DecisionResult(choice="tutor", prob=0.6)))
        d_teacher = _decide(role="teacher", dm=_StubDecisionModel(DecisionResult(choice="tutor", prob=0.6)))
    assert d_student.business == "capability"  # 未过学生端门槛
    assert d_teacher.business == "tutor"


def test_role_override_cleared_restores_default():
    with _role_score("teacher", 0.95):
        blocked = _decide(dm=_StubDecisionModel(DecisionResult(choice="tutor", prob=0.6)))
    after = _decide(dm=_StubDecisionModel(DecisionResult(choice="tutor", prob=0.6)))
    assert blocked.business == "capability"
    assert after.business == "tutor"


# ── 业务自述的更高门槛：内核只认「这个业务声明了门槛」，不认业务键 ──
def _runtime_with_declared(name: str, score: float) -> AgentRuntime:
    """复制生产清单，只给某个业务加 ``min_adopt_score``（``replace`` 不改原对象）。"""
    manifests = {k: replace(v) for k, v in _rt().manifests.items()}
    manifests[name] = replace(manifests[name], min_adopt_score=score)
    return AgentRuntime(manifests)


def test_business_declared_gate_blocks_and_adopts():
    rt = _runtime_with_declared("tasks", 0.9)
    blocked = _decide(rt=rt, dm=_StubDecisionModel(DecisionResult(choice="tasks", prob=0.6)))
    adopted = _decide(rt=rt, dm=_StubDecisionModel(DecisionResult(choice="tasks", prob=0.95)))
    assert blocked.business == "capability"
    assert adopted.business == "tasks"
    assert adopted.extra["min_adopt_score"] == 0.9


def test_declared_gate_is_business_agnostic():
    """门控不认识任何业务键：给一个**清单里本来没有**的业务声明门槛也照样生效。

    这是「内核不许硬编码 capability / tasks 之类字面量」的行为证明——换成源码扫描会
    被 docstring 里的举例干扰，行为证明更稳。
    """
    manifests = {k: replace(v) for k, v in _rt().manifests.items()}
    manifests["calendar"] = SubAgentManifest(
        business="calendar",
        name="课程表助手",
        description="查询与调整课程表",
        roles=["teacher", "student"],
        priority=99,
        min_adopt_score=0.8,
    )
    rt = AgentRuntime(manifests)
    blocked = _decide(rt=rt, dm=_StubDecisionModel(DecisionResult(choice="calendar", prob=0.6)))
    adopted = _decide(rt=rt, dm=_StubDecisionModel(DecisionResult(choice="calendar", prob=0.85)))
    assert blocked.business == "capability"
    assert adopted.business == "calendar"


# ── LLM 分类的 confidence 走同一张门控表 ──
def test_llm_confidence_below_gate_falls_to_guide():
    """此前 LLM 的 confidence 只被记进 extra，从不参与采纳判断（ADR-0107 修掉）。"""
    provider = RoutingFakeProvider(RoutingDecision(business="tutor", confidence=0.2))
    d = _decide(provider=provider, strategy="llm")
    assert d.business == "capability"
    assert (d.extra.get("rejected") or [{}])[0].get("primitive") == "llm"


def test_llm_confidence_meets_gate_adopts():
    provider = RoutingFakeProvider(RoutingDecision(business="tutor", confidence=0.9))
    d = _decide(provider=provider, strategy="llm")
    assert d.business == "tutor"
    assert d.extra["routed_by"] == "llm"


def test_llm_confidence_unreported_is_not_treated_as_zero():
    """``confidence is None`` = 模型没自报，不作比较。

    实测依据（ticket 13）：deepseek 在 44 条用例里多次不填该字段；按 ``0.0`` 参与
    0.5 门控会连带挡掉 6 条**正确**的路由。
    """
    provider = RoutingFakeProvider(RoutingDecision(business="tutor", confidence=None))
    d = _decide(provider=provider, strategy="llm")
    assert d.business == "tutor"
    assert d.extra["confidence"] is None


# ── 交叉校验（consensus，可选策略）──
def test_consensus_adopts_only_when_primitives_agree():
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.9))
    provider = RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.9))
    d = _decide(dm=dm, provider=provider, strategy="consensus")
    assert d.business == "tasks"
    assert d.extra["routed_by"] == "consensus"


def test_consensus_disagreement_falls_to_guide():
    """不一致 → 不采纳任一原语，落无命中引导（宁可不知道，也不自信地答非所问）。"""
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.9))
    provider = RoutingFakeProvider(RoutingDecision(business="tutor", confidence=0.9))
    d = _decide(dm=dm, provider=provider, strategy="consensus")
    assert d.business == "capability"
    assert d.extra["routed_by"] == "default"
    rejected = d.extra.get("rejected") or []
    assert any(r.get("disagreement") == ["tasks", "tutor"] for r in rejected)


def test_consensus_runs_both_primitives():
    """交叉校验的代价是**每轮多一次 LLM 往返**，故不进默认策略——这里守住它确实两个都跑。"""
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.9))
    provider = _CountingRoutingProvider(RoutingDecision(business="tasks", confidence=0.9))
    d = _decide(dm=dm, provider=provider, strategy="consensus")
    assert d.business == "tasks"
    assert dm.calls == 1  # 决策模型被调用
    assert provider.routing_calls == 1  # LLM 分类器也被调用（这就是那次额外往返）


def test_consensus_not_adopted_when_one_primitive_below_gate():
    """一边过门控、一边不过 → 不采纳（门控对两个原语同等生效）。"""
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.9))
    provider = RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.1))
    d = _decide(dm=dm, provider=provider, strategy="consensus")
    assert d.business == "capability"


# ── 动作直配仍不受门控影响（ADR-0081）──
def test_action_direct_match_bypasses_gate():
    from agent_core import IntentSignal

    runtime = _rt()
    dm = _StubDecisionModel(DecisionResult(choice="tutor", prob=0.01))
    deps = RuntimeDeps(provider=RoutingFakeProvider(None), decision_model=dm)
    with _strategy("decision"):
        d = asyncio.run(
            runtime.decide(
                IntentSignal(text="", action="task_generate"),
                role="teacher",
                deps=deps,
            )
        )
    assert d.business == "tasks"  # 动作直配命中，不经过门控
    assert d.extra["routed_by"] == "action"
    assert dm.calls == 0
