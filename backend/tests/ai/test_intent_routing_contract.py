"""动作直配内核契约（T02）：结构化动作 → business 的等值匹配。

接缝：唯一裁决点 ``AgentRuntime.decide``。所有断言打在它的返回值上，不断言内部走了哪一级。

覆盖：
- 动作归属唯一性（无孤儿 / 无悬空 / 不受清单顺序影响）
- 动作命中且角色可见 → 正确 business
- 动作命中但角色不可见 → 显式 ``action_not_visible``，**不是**静默回落可见集首个
- 未知动作 → 容错回落文本路由，不报错
- 纯文本调用（不带 action）结果与改动前逐条一致（由 test_agent_runtime 的回归表钉死）
"""
from __future__ import annotations

import asyncio
import random

from agent_core import IntentSignal
from agent_core.ports import RuntimeDeps
from agent_core.router import match_action
from agent_core.runtime import AgentRuntime
from app.domain.safety import StudentSafety
from tests.utils.fake_provider import FakeLLMProvider


def _rt() -> AgentRuntime:
    return AgentRuntime.discover()


def _deps(role: str) -> RuntimeDeps:
    return RuntimeDeps(
        provider=FakeLLMProvider(),
        safety=StudentSafety() if role == "student" else None,
    )


async def _decide(signal: IntentSignal, *, role: str) -> object:
    return await _rt().decide(signal, role=role, deps=_deps(role))


# ── 动作归属声明 ──
def test_question_manifest_declares_both_actions():
    m = AgentRuntime.discover().manifests.get("question")
    assert m is not None
    assert m.actions == ["task_generate", "task_question_regenerate"]


def test_match_action_helper():
    manifests = AgentRuntime.discover().manifests
    assert match_action("task_generate", manifests) == "question"
    assert match_action("task_question_regenerate", manifests) == "question"
    # 空动作 / 未知动作 → None（交给文本路由）
    assert match_action("", manifests) is None
    assert match_action("nonexistent_action", manifests) is None


def test_action_ownership_is_unique():
    """每个已声明的动作恰好一个归属 business：无孤儿、无悬空（两业务同持一个动作）。"""
    manifests = AgentRuntime.discover().manifests
    owner_of: dict[str, str] = {}
    for biz, m in manifests.items():
        for action in m.actions:
            assert action not in owner_of, (
                f"动作 {action!r} 同时被 {owner_of.get(action)} 与 {biz} 声明，"
                "唯一性由契约测试保证，动作直配无需排序规则"
            )
            owner_of[action] = biz
    # 本轮核心声明：出题助手拥有两个动作
    assert owner_of["task_generate"] == "question"
    assert owner_of["task_question_regenerate"] == "question"


# ── 动作直配路由结果 ──
def test_decide_action_routes_teacher_to_question():
    decision = asyncio.run(_decide(IntentSignal(text="", action="task_generate"), role="teacher"))
    assert decision.business == "question"
    assert decision.name == "出题助手"
    assert decision.extra.get("routed_by") == "action"


def test_decide_action_with_text_still_precedes_text_routing():
    # 动作键命中即路由，不被文本「出几道」之外的内容干扰（优先级竞争被消除）。
    decision = asyncio.run(
        _decide(IntentSignal(text="帮我讲讲这道题", action="task_generate"), role="teacher")
    )
    assert decision.business == "question"
    assert decision.extra.get("routed_by") == "action"


def test_decide_action_not_visible_for_student_is_explicit():
    # 出题助手仅教师可见；学生打该动作 → 显式不可见，绝不静默落成 tutor/可见集首个。
    decision = asyncio.run(_decide(IntentSignal(text="", action="task_generate"), role="student"))
    assert decision.business is None
    assert decision.name is None
    assert decision.extra.get("reason") == "action_not_visible"
    assert decision.extra.get("action") == "task_generate"


def test_decide_unknown_action_falls_back_to_text_routing():
    # 未知动作：容错回落自然语言路由，不报错。
    decision = asyncio.run(
        _decide(IntentSignal(text="帮我出几道数学题", action="does_not_exist"), role="teacher")
    )
    assert decision.business == "question"


# ── 顺序无关：打乱清单顺序结果不变 ──
def test_action_match_order_independent():
    base = AgentRuntime.discover().manifests
    for action in ("task_generate", "task_question_regenerate"):
        keys = list(base.keys())
        random.Random(0).shuffle(keys)
        shuffled = {k: base[k] for k in keys}
        rt = AgentRuntime(shuffled)
        decision = asyncio.run(
            rt.decide(IntentSignal(text="", action=action), role="teacher", deps=_deps("teacher"))
        )
        assert decision.business == "question", f"{action} 在打乱清单后仍应变 question"
