"""决策模型路由：``decide`` 接缝的回归（T08，ticket 08）。

主接缝 = ``AgentRuntime.decide`` 返回值（沿用 ai-intent-routing 测试缝）：只断言
「信号 + 角色 + history + deps → 路由决策」，不碰内部级别。决策模型用内存桩，
无网络 / 无权重依赖。

覆盖（对应 spec 验收）：
- 决策模型可用 → 按返回业务路由（``routed_by == "decision"``）；
- 决策模型不可用 / 返回 ``None`` / 返回不可见业务 → 回落 LLM 分类或兜底助手；
- history 进入决策模型的 ``state``（实现「每轮保持所有消息上下文」）；
- 续接「三年级」留 tasks、作答「选B」交 tutor（golden eval，根除两个已确认 bug）；
- 动作直配（ADR-0081）仍排在决策模型之前，不受影响。
"""
from __future__ import annotations

import asyncio

from agent_core import IntentSignal
from agent_core.ports import DecisionModel, DecisionResult, RuntimeDeps
from agent_core.runtime import AgentRuntime
from app.domain.safety import StudentSafety
from tests.utils.fake_provider import FakeLLMProvider


class _StubDecisionModel(DecisionModel):
    """内存桩：返回预设 ``DecisionResult``；记录收到的 ``state``。"""

    def __init__(self, result: DecisionResult | None = None, *, available: bool = True):
        self._result = result
        self._available = available
        self.states: list[str] = []

    def available(self) -> bool:
        return self._available

    async def decide(self, *, state: str, options):  # noqa: ANN001 — 测试桩
        self.states.append(state)
        return self._result


class _ContinuationStub(DecisionModel):
    """模拟「读上下文做决策」的模型：补参数 → tasks；作答 → tutor。

    仅用于 golden eval：验证 runtime 把 history + 当前消息喂给模型、并按模型答案路由，
    不依赖真实 Laya 权重。判定只看 state 末尾的「当前消息」行，不被历史里的词污染。
    """

    def __init__(self) -> None:
        self.states: list[str] = []

    def available(self) -> bool:
        return True

    @staticmethod
    def _current_message(state: str) -> str:
        for line in reversed(state.splitlines()):
            if line.startswith("user:"):
                return line[5:].strip()
        return ""

    async def decide(self, *, state: str, options):  # noqa: ANN001 — 测试桩
        self.states.append(state)
        current = self._current_message(state)
        if any(k in current for k in ("三年级", "数学", "换成一年级", "再出几道", "换一题")):
            return DecisionResult(choice="tasks", prob=0.9)
        if any(k in current for k in ("选B", "我不会", "为什么")):
            return DecisionResult(choice="tutor", prob=0.88)
        return DecisionResult(choice="tutor", prob=0.5)


def _rt() -> AgentRuntime:
    return AgentRuntime.discover()


def _deps(*, dm: DecisionModel | None, role: str) -> RuntimeDeps:
    return RuntimeDeps(
        provider=FakeLLMProvider(),
        safety=StudentSafety() if role == "student" else None,
        decision_model=dm,
    )


def _decide(message, *, role: str = "teacher", dm=None, history=None):
    rt = _rt()
    return asyncio.run(
        rt.decide(message, role=role, deps=_deps(dm=dm, role=role), history=history)
    )


def _prior_tasks_history() -> list[dict]:
    return [
        {
            "role": "user",
            "content": "请为「图形的运动（轴对称）」出一道四年级数学选择题",
        },
        {"role": "assistant", "content": "这是一张轴对称题卡"},
    ]


# ── 决策模型可用 → 按返回业务路由 ──
def test_decision_model_routes_when_available():
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.92))
    d = _decide("随便一句", dm=dm)
    assert d.business == "tasks"
    assert d.extra.get("routed_by") == "decision"
    assert d.extra.get("prob") == 0.92
    assert "user: 随便一句" in dm.states[-1]


# ── 决策模型不可用 → 回落 LLM 分类；LLM 也不可用（普通替身）→ 兜底助手 ──
def test_decision_model_unavailable_falls_back_to_default():
    d = _decide("帮我出2道四年级数学题", dm=None)
    assert d.business == "tutor"  # 兜底助手（规则已移除，ADR-0104）
    assert d.extra.get("routed_by") == "default"


def test_decision_model_returns_none_falls_back():
    dm = _StubDecisionModel(None, available=True)
    d = _decide("帮我出几道数学题", dm=dm)
    assert d.business == "tutor"
    assert d.extra.get("routed_by") == "default"


def test_decision_model_choice_not_visible_falls_back():
    dm = _StubDecisionModel(DecisionResult(choice="nonexistent_biz", prob=0.9))
    d = _decide("随便一句", dm=dm)
    assert d.business != "nonexistent_biz"
    assert d.business in _rt().visible_businesses("teacher")
    assert d.extra.get("routed_by") == "default"


# ── history 进入决策模型 state（每轮保持所有消息上下文） ──
def test_history_reaches_decision_model_state():
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.9))
    _decide("三年级", history=_prior_tasks_history(), dm=dm)
    state = dm.states[-1]
    assert "请为「图形的运动（轴对称）」出一道四年级数学选择题" in state
    assert "这是一张轴对称题卡" in state
    assert "user: 三年级" in state


# ── golden eval：续接留 tasks、作答交 tutor（根除两个已确认 bug） ──
def test_continuation_change_grade_stays_tasks():
    dm = _ContinuationStub()
    d = _decide("三年级", history=_prior_tasks_history(), dm=dm)
    assert d.business == "tasks"
    assert d.extra.get("routed_by") == "decision"


def test_continuation_answer_routes_tutor():
    dm = _ContinuationStub()
    d = _decide("选B", history=_prior_tasks_history(), dm=dm)
    assert d.business == "tutor"
    assert d.extra.get("routed_by") == "decision"


def test_new_conversation_first_turn_chu_yi_dao_routes_tasks():
    """首轮「出一道」：由决策模型按上下文判到 tasks（规则已移除，ADR-0104）。"""
    dm = _StubDecisionModel(DecisionResult(choice="tasks", prob=0.9))
    d = _decide("请为「图形的运动（轴对称）」出一道四年级数学选择题", dm=dm)
    assert d.business == "tasks"
    assert d.extra.get("routed_by") == "decision"


# ── 动作直配（ADR-0081）仍在决策模型之前 ──
def test_action_direct_match_prior_to_decision_model():
    dm = _StubDecisionModel(DecisionResult(choice="tutor", prob=0.99))
    rt = _rt()
    d = asyncio.run(
        rt.decide(
            IntentSignal(text="", action="task_generate"),
            role="teacher",
            deps=_deps(dm=dm, role="teacher"),
        )
    )
    assert d.business == "tasks"  # 动作直配命中
    assert d.extra.get("routed_by") == "action"
    assert dm.states == []  # 决策模型根本没被调用
