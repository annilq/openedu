"""``capability`` 能力自述与超范围引导 SubAgent 契约测试（ADR-0079，零 LLM）。

守住四条（全部确定性、不接真实模型）：

- 能力自述意图（你能做什么 / 你会什么 / 怎么用你 / 你是谁 …）路由到 ``capability``，
  而非 ``tutor`` / ``query``；
- ``guide`` 的写意图（priority 20）不被 ``capability``（16）抢走；
- ``query`` 的读意图（priority 12）不被 ``capability`` 抢走；
- 能力清单为服务端固定目录（非 LLM 生成），按角色分叉且内容确定；
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


def test_priority_sits_between_query_and_guide():
    """priority=16 是功能本身：高于 query(12) 才能接走「你能查什么」类元问题
    （否则被 query 的 requires_tool_data 硬失败），低于 guide(20) 才不抢写意图。
    """
    manifests = discover_subagent_manifests()
    assert manifests["capability"].priority == 16
    assert manifests["query"].priority < manifests["capability"].priority < manifests["guide"].priority


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


def test_guide_write_intent_not_stolen():
    assert _route("帮我创建一个任务", "teacher") == "guide"


def test_query_read_intent_not_stolen():
    assert _route("查一下我的错题", "teacher") == "query"
    assert _route("今天有什么作业", "teacher") == "query"


def test_out_of_scope_falls_to_tutor():
    # 明显超范围（天气）不归 capability，落 tutor 兜底（不硬失败）。
    assert _route("今天天气怎么样", "student") == "tutor"


# ───────────── 3. 固定目录 + 零 LLM ─────────────


def test_catalog_splits_by_role():
    student = capability_catalog("student")
    teacher = capability_catalog("teacher")
    assert student and teacher
    assert student != teacher  # 师生能力清单不同


def test_run_yields_fixed_text_and_never_calls_provider():
    """回复文本等于服务端固定目录——内容确定、不依赖任何模型调用（最强零 LLM 证明）。"""
    agent = CapabilitySubAgent(provider=FakeLLMProvider())
    events = asyncio.run(_collect(agent, "你能做什么", "student"))
    msgs = [ev for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE]
    assert msgs, "capability 必须产出 ASSISTANT_MESSAGE"
    assert msgs[0].text == capability_response("student")

    # 教师端拿到的是教师清单
    events_t = asyncio.run(_collect(agent, "你能做什么", "teacher"))
    msgs_t = [ev for ev in events_t if ev.eventType == EVENT_ASSISTANT_MESSAGE]
    assert msgs_t[0].text == capability_response("teacher")


def test_tutor_system_prompt_includes_scope_guidance():
    """tutor 偶发接住的超范围问题也能自我说明（安全锁补一句常量尾句）。"""
    prompt = tutor_system_prompt(grade=4, subject="数学")
    assert "用一句话说明你能做什么" in prompt
    # 签名未变：仍随 (grade, subject) 生成
    assert "4年级" in prompt and "数学" in prompt
