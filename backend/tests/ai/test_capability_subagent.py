"""``capability`` 能力自述与超范围引导 SubAgent 契约测试（ADR-0079 / ADR-0097 / ADR-0104 / ADR-0105，零 LLM）。

守住六条（全部确定性、不接真实模型）：

- 能力清单为 **manifests 的投影**（ADR-0097：单一事实源，非 LLM 生成、非手抄），
  按角色过滤可见 business，无 query/guide 残留字样；
- 超范围问题落 ``tutor``（显式路由时，不硬失败），且 ``tutor_system_prompt`` 含超范围自述句式；
- subagent 不持有工具、不调用 provider（零 LLM）；
- ``priority=16``：规则时代它压过 tasks(14) 的泛词；ADR-0104 移除规则路由后 priority
  只剩「清单呈现顺序」语义，16 保持清单首位；
- ADR-0105：``fallback_guide=True``——都没有命中（策略原语均不决策）时由本业务给出
  能力引导；契约：全清单至多一个业务声明、且对师生双端可见（否则该角色的无命中
  会静默退到 priority 最小者）。

ADR-0104：原「能力自述问句路由到 capability」一组测试随规则路由移除而删除——
「你能做什么」类元问题由 LLM / 决策模型按能力清单路由，不再是词表可钉的东西。
"""
from __future__ import annotations

import asyncio
from typing import Any

from agent_core.protocol import EVENT_ASSISTANT_MESSAGE
from agent_core.registry import discover_subagent_manifests
from agent_core.subagent import SubAgentContext
from app.ai.subagents.capability import (
    CapabilitySubAgent,
    capability_catalog,
    capability_response,
)
from app.domain.safety import tutor_system_prompt
from tests.utils.fake_provider import FakeLLMProvider


async def _collect(agent, message: str, role: str) -> list[Any]:
    ctx = SubAgentContext(role=role, message=message)
    return [ev async for ev in agent.run(message, ctx)]


# ───────────── 1. 清单与优先级不变量 ─────────────


def test_manifest_declares_capability_and_dual_role():
    m = discover_subagent_manifests()["capability"]
    assert (m.business, m.name) == ("capability", "能力自述")
    assert m.roles == ["teacher", "student"]


def test_manifest_declares_unique_fallback_guide():
    """ADR-0105：至多一个业务声明 ``fallback_guide``，且就是 capability、双端可见。

    都不命中时该业务给出「自身能力引导」；若声明不唯一，无命中落点随清单顺序漂移；
    若对某角色不可见，该角色的无命中会静默退到 priority 最小者（回到「执行体兜底」）。
    """
    manifests = discover_subagent_manifests()
    declared = [b for b, m in manifests.items() if m.fallback_guide]
    assert declared == ["capability"], f"无命中引导应仅 capability 声明：{declared}"
    guide = manifests["capability"]
    for role in ("teacher", "student"):
        assert role in guide.roles, f"无命中引导必须对 {role} 可见"


def test_priority_sits_above_all_business_domains():
    """priority=16 是清单呈现顺序的第一位（ADR-0104 后不再「压词」）。

    规则路由时代它必须压过 tasks(14) 的泛词（「查 / 有哪些」），否则「你能查什么」
    类元问题会被 requires_tool_data 硬失败；规则移除后该竞争消失，16 的现实语义只是
    能力清单中 capability 之后按序排。ADR-0105：都没有命中时的落点由 ``fallback_guide``
    声明（capability），与 priority 数值无关。
    ADR-0098：students / question 域吸收进 tasks 后，被排序的域只剩两个执行体。
    """
    manifests = discover_subagent_manifests()
    assert manifests["capability"].priority == 16
    for lower in ("tasks", "tutor"):
        assert manifests["capability"].priority > manifests[lower].priority


def test_agent_carries_no_tools():
    """不持有工具：能力自述是固定目录，无需模型，也绝不能因工具 loop 去调 provider。"""
    agent = CapabilitySubAgent(provider=FakeLLMProvider())
    assert agent.tools == []


# ───────────── 2. 清单 = manifests 投影 + 零 LLM ─────────────


def test_catalog_is_manifest_projection():
    """ADR-0097：清单从 manifests 生成——新增/调整业务只需改 manifest，此处自动跟随。

    同时是「无 query/guide 残留」的守卫：旧手抄清单在两者解散后仍在描述
    「查询学情 / 引导发布」，这类漂移从此不可能再发生。
    """
    manifests = discover_subagent_manifests()
    for role in ("student", "teacher"):
        lines = capability_catalog(role)
        assert lines, f"{role} 清单为空"
        joined = "\n".join(lines)
        # 每个可见业务（除 capability 自身）各一行：name + description
        for biz, m in manifests.items():
            if biz == "capability" or role not in m.roles:
                continue
            assert f"{m.name}：{m.description}" in lines, f"{role} 清单缺 {biz}"
        # capability 自身不出现在自己的清单里
        assert "能力自述" not in joined
        # 已解散业务的字样不得残留
        assert "学情查询" not in joined and "任务引导" not in joined


def test_catalog_order_follows_priority():
    """呈现顺序 = 路由优先级降序（主能力在前），与用户提问的命中概率一致。

    ADR-0098：students / question 域并入 tasks 后，清单只剩两个执行体——
    tasks（学情 + 出题）在前，tutor（伴学）收尾。
    """
    lines = capability_catalog("teacher")
    assert lines[0].startswith("任务学情与出题助手")
    assert lines[-1].startswith("伴学答疑")


def test_boundary_text_mentions_draft_and_confirmation():
    """边界话术（ADR-0097 改写）：起草 + 发布前确认，且不暗示学生有写能力。"""
    teacher = capability_response("teacher")
    assert "起草任务与题目" in teacher and "请你确认" in teacher
    student = capability_response("student")
    assert "起草任务" not in student  # create_draft 对学生不可用，不得暗示


def test_run_yields_fixed_text_and_never_calls_provider():
    """回复文本等于服务端固定目录——内容确定、不依赖任何模型调用（最强零 LLM 证明）。"""
    agent = CapabilitySubAgent(provider=FakeLLMProvider())
    events = asyncio.run(_collect(agent, "你能做什么", "student"))
    msgs = [ev for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE]
    assert msgs, "capability 必须产出 ASSISTANT_MESSAGE"
    assert msgs[0].text == capability_response("student")

    # 教师端拿到的是教师边界 + 清单
    events_t = asyncio.run(_collect(agent, "你能做什么", "teacher"))
    msgs_t = [ev for ev in events_t if ev.eventType == EVENT_ASSISTANT_MESSAGE]
    assert msgs_t[0].text == capability_response("teacher")


def test_tutor_system_prompt_includes_scope_guidance():
    """tutor 偶发接住的超范围问题也能自我说明（安全锁补一句常量尾句）。"""
    prompt = tutor_system_prompt(grade=4, subject="数学")
    assert "用一句话说明你能做什么" in prompt
    # 签名未变：仍随 (grade, subject) 生成
    assert "4年级" in prompt and "数学" in prompt
