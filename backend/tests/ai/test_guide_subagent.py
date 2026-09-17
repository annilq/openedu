"""``guide`` 任务引导 SubAgent 契约测试（写意图的出口）。

**真机报障（2026-09-17）**：家长对助手说「帮我创建一个任务，包含四年级数学题」，
得到的是「我这边只能查询学习数据，不能生成或派发任务…请到『任务/作业』相关页面操作」。

这句回答本身**没有幻觉**——助手确实只读。问题出在两个叠加的缺口：

1. **路由**：``query`` 的 ``triggers`` 含泛词「任务 / 作业」且 ``priority=12`` 最高，
   于是「创建任务」这类**写意图**被只读的查询 agent 接走（实测确认）；
2. **引导断链**：模型让用户「去任务/作业页面」，而卡片协议只下发结构化字段
   （``title/items/stats/text``），**没有任何位置能放那个入口**——用户被告知去别处，
   却拿不到别处。

本文件守住四条（全部确定性、不接真实模型）：

- 写意图归 ``guide``（含真机原句），而**查询意图仍归 ``query``**——这是本 subagent
  最容易搞坏的地方：把词表放宽一点，它就开始抢查询；
- 娃娃端看不到 ``guide``（没有布置任务的入口，也不能因此暴露写能力的暗示）；
- ``priority`` 必须始终压过 ``query``（结构不变量，防止将来被调低而静默退化）；
- 卡片载荷的形状与 target 值域：target 是**受控枚举**，不在值域内即视为契约破损。
"""
from __future__ import annotations

import asyncio
from typing import Any

from agent_core.ports import RuntimeDeps
from agent_core.protocol import EVENT_ASSISTANT_MESSAGE, EVENT_DATA
from agent_core.registry import build_subagent, discover_subagent_manifests
from agent_core.runtime import AgentRuntime
from agent_core.subagent import SubAgentContext
from app.ai.subagents.guide import (
    KIND,
    TARGET_CREATE_TASK,
    TARGET_QUESTION_BANK,
    GuideSubAgent,
)
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


def _run_guide(message: str = "帮我创建一个任务", role: str = "parent") -> list[Any]:
    agent = build_subagent(
        discover_subagent_manifests(), "guide", provider=FakeLLMProvider()
    )
    assert isinstance(agent, GuideSubAgent)
    return asyncio.run(_collect(agent, message, role))


# ───────────────────────── 1. 清单与优先级不变量 ─────────────────────────


def test_manifest_declares_guide_and_is_parent_only():
    m = discover_subagent_manifests()["guide"]
    assert (m.business, m.name) == ("guide", "任务引导")
    assert m.roles == ["parent"]
    # hints 必须留空：写意图要的是高精度，启发式兜底会把查询意图一并抢走。
    assert m.hints == []


def test_priority_always_beats_query():
    """优先级是这条路由的**唯一**依据，回调一点就静默退化回真机那个回答。

    query 的 triggers 含泛词「任务」，只要 guide 的 priority 不高于它，
    「创建任务」就会被只读查询接走——所以这不是调参，是功能本身。
    """
    manifests = discover_subagent_manifests()
    assert manifests["guide"].priority > manifests["query"].priority


def test_agent_carries_no_tools():
    """不持有工具：它对用户说的是「我不能写」，不能自己带一把写工具。

    也让 runtime 走一次性 ``run``（无 tool loop），省掉一轮模型往返。
    """
    agent = GuideSubAgent(provider=FakeLLMProvider())
    assert agent.tools == []


# ───────────────────────── 2. 路由边界（真机原句） ─────────────────────────


def test_reported_write_intent_goes_to_guide():
    """真机报障的原句——修复前它路由到 ``query``。"""
    assert _route("帮我创建一个任务，包含四年级数学题", "parent") == "guide"
    assert _route("创建一个任务", "parent") == "guide"
    assert _route("帮我建个作业，放2道四年级数学题", "parent") == "guide"


def test_read_intent_still_goes_to_query():
    """词表放宽的第一批受害者就是这些句子——它们必须仍归只读查询。"""
    assert _route("查一下我创建过的任务", "parent") == "query"
    assert _route("今天有什么作业", "parent") == "query"
    assert _route("我的错题本里有哪些题", "parent") == "query"


def test_question_intent_still_goes_to_question():
    assert _route("帮我出2道四年级数学题", "parent") == "question"


def test_child_never_sees_guide():
    """娃娃端没有布置任务入口，也不该被引导到一个它进不去的页面。"""
    assert "guide" not in AgentRuntime.discover().visible_businesses("child")
    assert _route("帮我创建一个任务", "child") != "guide"


# ───────────────────────── 3. 卡片形状与 target 值域 ─────────────────────────


def test_card_is_typed_and_carries_whitelisted_targets():
    events = _run_guide()
    data = [ev for ev in events if ev.eventType == EVENT_DATA]
    assert data, "引导卡必须产出 DATA 帧"
    payload = data[0].data
    assert payload["type"] == KIND
    result = payload["result"]
    assert result["title"] and result["text"]

    allowed = {TARGET_CREATE_TASK, TARGET_QUESTION_BANK}
    actions = result["actions"]
    assert actions, "引导卡的全部价值就是那个出口"
    for action in actions:
        assert action["label"], "有按钮没文案"
        assert action["target"] in allowed, f"target 越出受控值域：{action['target']}"


def test_text_says_why_not_just_no():
    """收尾话术必须给出**理由**：只回「我不能创建」，用户只会再问一遍。"""
    events = _run_guide()
    finish = [ev for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE]
    assert finish, "缺收尾 ASSISTANT_MESSAGE"
    assert "布置任务" in finish[0].text
