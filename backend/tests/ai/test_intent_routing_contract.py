"""动作直配内核契约（T02 / ADR-0104）：结构化动作 → business 的等值匹配。

接缝：唯一裁决点 ``AgentRuntime.decide``。所有断言打在它的返回值上，不断言内部走了哪一级。

覆盖：
- 动作归属唯一性（无孤儿 / 无悬空 / 不受清单顺序影响）
- 动作命中且角色可见 → 正确 business
- 动作命中但角色不可见 → 显式 ``action_not_visible``，**不是**静默回落可见集首个
- 未知动作 → 容错回落文本路由（策略原语：LLM 分类 / 无命中引导），不报错

ADR-0104：规则（关键词/启发式）路由已整体移除——``classify`` / ``Classification`` /
``trigger_patterns`` / ``intent_schemas`` 连同其契约测试一并删除；业务选择由 LLM /
决策模型按「对话上下文 + 能力清单」决定，纯文本路由的语义正确性不再是单测可钉的
东西（由路由原语测试覆盖机制，由真实模型负责语义）。
"""
from __future__ import annotations

import asyncio
import random

from agent_core import IntentSignal
from agent_core.adapters.llm_route import RoutingDecision
from agent_core.ports import RuntimeDeps
from agent_core.router import match_action
from agent_core.runtime import AgentRuntime
from app.domain.safety import StudentSafety
from tests.utils.fake_provider import FakeLLMProvider, RoutingFakeProvider


def _rt() -> AgentRuntime:
    return AgentRuntime.discover()


def _deps(role: str, *, provider=None) -> RuntimeDeps:
    return RuntimeDeps(
        provider=provider if provider is not None else FakeLLMProvider(),
        safety=StudentSafety() if role == "student" else None,
    )


async def _decide(signal: IntentSignal, *, role: str, provider=None) -> object:
    return await _rt().decide(signal, role=role, deps=_deps(role, provider=provider))


# ── 动作归属声明 ──
def test_tasks_manifest_declares_all_actions():
    # ADR-0098：question 域并入 tasks，task_generate 动作随迁
    m = AgentRuntime.discover().manifests.get("tasks")
    assert m is not None
    # ADR-0089：出题只声明「按规格出题」（task_generate）。判断题闭环（出题-判定-讲解）
    # 已整体下沉到子代理：出题从自由文本/上下文自主判定 judge 规格，判定由 tutor 从对话
    # 历史读答案，不再有 quiz_generate / quiz_judge / courseware_hint 动作键。
    assert m.actions == ["task_generate"]


def test_match_action_helper():
    manifests = AgentRuntime.discover().manifests
    assert match_action("task_generate", manifests) == "tasks"
    # 空动作 / 未知动作 → None（交给文本路由）
    assert match_action("", manifests) is None
    assert match_action("nonexistent_action", manifests) is None


# 已声明动作的**完整词表**：动作键 → 归属 business。每个动作在此写明「请求方」
# （谁产出 / 谁触发这个键）——这是兜住「孤儿（清单里声明了但无人请求）」与「悬空
# （有请求方但没在清单里声明）」的显式期望集合（spec L121 硬要求）。新增动作键必须
# 同时在 manifest 与本表各加一行；只加其一，本契约测试即失败。
_EXPECTED_ACTION_OWNERS: dict[str, str] = {
    # 请求方：客户端结构化出题（req.action=task_generate）
    "task_generate": "tasks",
}


def test_action_ownership_is_unique():
    """每个已声明的动作属于**恰好一个** business，且完整词表与期望集合一致：

    - 归属唯一（同一动作不被两业务同时声明）；
    - 无孤儿（清单里声明了但无人请求）；
    - 无悬空（有请求方但没在清单里声明）。
    """
    manifests = AgentRuntime.discover().manifests
    owner_of: dict[str, str] = {}
    for biz, m in manifests.items():
        for action in m.actions:
            assert action not in owner_of, (
                f"动作 {action!r} 同时被 {owner_of.get(action)} 与 {biz} 声明，"
                "唯一性由契约测试保证，动作直配无需排序规则"
            )
            owner_of[action] = biz
    # 完整词表比对：多一个（孤儿）或少一个（悬空）都会失败——动作名与清单不同步
    # 不再静默失效。归属不符也会失败（并打印差异）。
    mismatched = {
        k: (owner_of[k], _EXPECTED_ACTION_OWNERS[k])
        for k in owner_of.keys() & _EXPECTED_ACTION_OWNERS.keys()
        if owner_of[k] != _EXPECTED_ACTION_OWNERS[k]
    }
    assert owner_of == _EXPECTED_ACTION_OWNERS, (
        f"已声明动作与期望不一致：仅清单有（孤儿）="
        f"{sorted(set(owner_of) - set(_EXPECTED_ACTION_OWNERS))}，仅期望有（悬空）="
        f"{sorted(set(_EXPECTED_ACTION_OWNERS) - set(owner_of))}，归属不符="
        f"{ {k: f'{got}≠{want}' for k, (got, want) in mismatched.items()} }"
    )


# ── 动作直配路由结果 ──
def test_decide_action_routes_teacher_to_tasks():
    decision = asyncio.run(_decide(IntentSignal(text="", action="task_generate"), role="teacher"))
    assert decision.business == "tasks"
    assert decision.name == "任务学情与出题助手"
    assert decision.extra.get("routed_by") == "action"


def test_decide_action_with_text_still_precedes_text_routing():
    # 动作键命中即路由，不被文本「出几道」之外的内容干扰（优先级竞争被消除）。
    decision = asyncio.run(
        _decide(IntentSignal(text="帮我讲讲这道题", action="task_generate"), role="teacher")
    )
    assert decision.business == "tasks"
    assert decision.extra.get("routed_by") == "action"


def test_decide_action_routes_student_to_tasks():
    # 出题现已对师生双开（ADR-0081 §2.2）：学生打 task_generate → 直接路由 tasks。
    decision = asyncio.run(_decide(IntentSignal(text="", action="task_generate"), role="student"))
    assert decision.business == "tasks"
    assert decision.name == "任务学情与出题助手"
    assert decision.extra.get("routed_by") == "action"


def test_decide_action_not_visible_when_role_lacks_manifest():
    # 防御路径：动作命中但其归属 subagent 对当前角色不可见 → 显式 action_not_visible，
    # 不静默落成答非所问。用合成清单验证代码路径（tasks 现已双开，不再能触发此分支）。
    from agent_core.registry import SubAgentManifest

    m = SubAgentManifest(
        business="limited",
        name="受限助手",
        roles=["teacher"],  # 仅教师可见
        actions=["limited_action"],
    )
    rt = AgentRuntime({"limited": m})
    decision = asyncio.run(
        rt.decide(
            IntentSignal(text="", action="limited_action"),
            role="student",
            deps=_deps("student"),
        )
    )
    assert decision.business is None
    assert decision.name is None
    assert decision.extra.get("reason") == "action_not_visible"
    assert decision.extra.get("action") == "limited_action"


def test_decide_unknown_action_falls_back_to_text_routing():
    # 未知动作：容错回落自然语言路由（ADR-0104 后＝策略原语），不报错。
    # 用路由 LLM 桩注入「tasks」证明落的确实是文本路由那条路，而不是无命中引导。
    provider = RoutingFakeProvider(RoutingDecision(business="tasks", confidence=0.9))
    decision = asyncio.run(
        _decide(
            IntentSignal(text="帮我出几道数学题", action="does_not_exist"),
            role="teacher",
            provider=provider,
        )
    )
    assert decision.business == "tasks"
    assert decision.extra.get("routed_by") == "llm"


# ── T06：课件上下文 / 待判定态定向迁进信号（各有独立动作键） ──
# ADR-0089：courseware_hint / quiz_judge / quiz_generate 三个动作键已删除——课件提示由
# courseware 上下文触发，判断题出题/判定由 tasks / tutor 子代理自主驱动（文本/历史），
# 服务端不再在信号归一化阶段硬发射动作键。


# ── 顺序无关：打乱清单顺序结果不变 ──
def test_action_match_order_independent():
    base = AgentRuntime.discover().manifests
    for action in ("task_generate",):
        keys = list(base.keys())
        random.Random(0).shuffle(keys)
        shuffled = {k: base[k] for k in keys}
        rt = AgentRuntime(shuffled)
        decision = asyncio.run(
            rt.decide(IntentSignal(text="", action=action), role="teacher", deps=_deps("teacher"))
        )
        assert decision.business == "tasks", f"{action} 在打乱清单后仍应变 tasks"
