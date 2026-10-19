"""``capability`` 能力自述与超范围引导 SubAgent 契约测试（ADR-0079 / ADR-0097，零 LLM）。

守住六条（全部确定性、不接真实模型）：

- 能力自述意图（你能做什么 / 你会什么 / 怎么用你 / 你是谁 …）路由到 ``capability``，
  而非 ``tutor`` / ``tasks``；
- ``tasks`` 的写意图（「创建任务」类短语）不被 ``capability`` 抢走；
- ``tasks`` 的读意图（错题 / 作业）不被 ``capability`` 抢走；
- 能力清单为 **manifests 的投影**（ADR-0097：单一事实源，非 LLM 生成、非手抄），
  按角色过滤可见 business，无 query/guide 残留字样；
- 超范围问题落 ``tutor`` 兜底（不硬失败），且 ``tutor_system_prompt`` 含超范围自述句式；
- subagent 不持有工具、不调用 provider（零 LLM）。
"""
from __future__ import annotations

import asyncio
from typing import Any

from agent_core.ports import RuntimeDeps
from agent_core.protocol import EVENT_ASSISTANT_MESSAGE
from agent_core.registry import discover_subagent_manifests
from agent_core.runtime import AgentRuntime
from agent_core.subagent import SubAgentContext
from app.ai.subagents.capability import (
    CapabilitySubAgent,
    capability_catalog,
    capability_response,
)
from app.domain.safety import tutor_system_prompt
from tests.utils.fake_provider import FakeLLMProvider


def _route(text: str, role: str) -> str:
    runtime = AgentRuntime.discover()
    decision = asyncio.run(
        runtime.decide(text, role=role, deps=RuntimeDeps(provider=FakeLLMProvider()))
    )
    return decision.business or ""


async def _collect(agent, message: str, role: str) -> list[Any]:
    ctx = SubAgentContext(role=role, message=message)
    return [ev async for ev in agent.run(message, ctx)]


# ───────────── 1. 清单与优先级不变量 ─────────────


def test_manifest_declares_capability_and_dual_role():
    m = discover_subagent_manifests()["capability"]
    assert (m.business, m.name) == ("capability", "能力自述")
    assert m.roles == ["teacher", "student"]
    # hints 必须留空：能力自述要的是高精度，启发式兜底会把查询/讲解意图一并抢走。
    assert m.hints == []


def test_priority_sits_above_all_business_domains():
    """priority=16 是功能本身：压过 tasks(14)/question(12) 的泛词（「查 / 有哪些」），
    否则「你能查什么」类元问题会被 requires_tool_data 硬失败。
    写意图不冲突：tasks 的写触发词是「创建任务」等高精度短语，与自述问句无交集。
    ADR-0098：students 域吸收进 tasks 后，被压制的域少一个，16 仍高于全部执行体。
    """
    manifests = discover_subagent_manifests()
    assert manifests["capability"].priority == 16
    for lower in ("tasks", "question", "tutor"):
        assert manifests["capability"].priority > manifests[lower].priority


def test_agent_carries_no_tools():
    """不持有工具：能力自述是固定目录，无需模型，也绝不能因工具 loop 去调 provider。"""
    agent = CapabilitySubAgent(provider=FakeLLMProvider())
    assert agent.tools == []


# ───────────── 2. 路由边界 ─────────────


def test_capability_intent_routes_for_both_roles():
    for phrase in (
        "你能做什么", "你会什么", "你能帮我什么", "你有什么功能", "有什么功能",
        "怎么用你", "你是谁", "你是什么", "你能干什么",
    ):
        assert _route(phrase, "student") == "capability", phrase
        assert _route(phrase, "teacher") == "capability", phrase


def test_tasks_write_intent_not_stolen():
    assert _route("帮我创建一个任务", "teacher") == "tasks"


def test_tasks_read_intent_not_stolen():
    assert _route("查一下我的错题", "teacher") == "tasks"
    assert _route("今天有什么作业", "teacher") == "tasks"


def test_out_of_scope_falls_to_tutor():
    # 明显超范围（天气）不归 capability，落 tutor 兜底（不硬失败）。
    assert _route("今天天气怎么样", "student") == "tutor"


# ───────────── 3. 清单 = manifests 投影 + 零 LLM ─────────────


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
    """呈现顺序 = 路由优先级降序（主能力在前），与用户提问的命中概率一致。"""
    lines = capability_catalog("teacher")
    assert lines[0].startswith("任务学情助手")
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
