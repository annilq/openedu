"""``query`` SubAgent 契约测试（ADR-0033 决策 6 / 11 / 14）。

守护四件事，全部**确定性**、不接真实模型（CI 红线）：

1. **清单与装配**：``query`` 被发现、``tasks`` 已消失、``priority=12``（压住 question 的
   泛触发词）、SOP 真被读进 prompt；SubAgent 实例携带全部 7 个工具。
2. **路由边界**：带查询语境的问句（任务/作业/错题/复习）归 ``query``，
   「出题」意图仍归 ``question``；娃娃端可见 query 但「出题」仍被强制回 tutor。
3. **展示投影**（决策 11）：``render_tool_result`` 产出的卡片是前端 ``_CardTile`` 的形状
   （``{type, subject, stem}``、``stem`` 非空），错误结果不炸流。
4. **端到端 tool loop**：真 DB + 脚本化 provider 跑一轮，``TOOL_CALL`` → ``TOOL_RESULT``
   → ``DATA`` → ``ASSISTANT_MESSAGE`` 齐备；**娃娃端帧里不出现答案/解析**，家长端对照
   组证明这不是「数据为空」的假绿。
"""
from __future__ import annotations

import asyncio
import json
from typing import Any

from sqlmodel import Session

from agent_core.ports import RuntimeDeps, TextDelta, ToolCall
from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
)
from agent_core.registry import build_subagent, discover_subagent_manifests
from agent_core.runtime import AgentRuntime
from agent_core.subagent import SubAgentContext, run_with_tools
from app.ai.subagents.query import QuerySubAgent
from app.ai.subagents.query.render import render_cards
from app.ai.subagents.query.tools._shared import ANSWER_FIELDS
from app.ai.subagents.query.tools.registry import QUERY_TOOLS
from app.ai.subagents.tutor import TutorSubAgent
from app.core.db import engine
from tests.ai.test_query_tools_contract import (
    EXPECTED_TOOL_NAMES,
    _setup,  # 复用同一套数据装置（1 家长 + 2 娃娃 + 任务 + 错题 + 未派发草稿）
)
from tests.utils.fake_provider import FakeLLMProvider

# ───────────────────────── 1. 清单与装配 ─────────────────────────


def test_manifest_absorbs_tasks_and_declares_query():
    manifests = discover_subagent_manifests()
    assert "query" in manifests and "tasks" not in manifests
    m = manifests["query"]
    assert (m.business, m.name) == ("query", "学情查询")
    assert m.roles == ["parent", "child"]
    assert m.priority == 12
    assert m.skills == ["query_sop"]
    assert "学情查询 SOP" in m.skill_prompt
    # 查不到不许估算的硬约束必须在 SOP 里（决策 14）
    assert "查不到" in m.skill_prompt


def test_agent_carries_all_query_tools():
    agent = build_subagent(discover_subagent_manifests(), "query", provider=FakeLLMProvider())
    assert isinstance(agent, QuerySubAgent)
    assert [t.name for t in agent.tools] == EXPECTED_TOOL_NAMES
    assert agent.max_turns == 3  # 内默认：查询 1–2 跳足够
    assert [t.name for t in QUERY_TOOLS] == EXPECTED_TOOL_NAMES


def test_initial_system_carries_role_hint_and_sop():
    agent = QuerySubAgent(provider=FakeLLMProvider())
    child = agent.initial_system("今天有什么作业", SubAgentContext(role="child", skills="SOP-X"))
    parent = agent.initial_system("孩子错题", SubAgentContext(role="parent", skills="SOP-X"))
    assert "娃娃本人" in child and "娃娃本人" not in parent
    assert "家长" in parent
    assert child.endswith("SOP-X") and parent.endswith("SOP-X")


# ───────────────────────── 2. 路由边界 ─────────────────────────


def _route(text: str, role: str) -> str:
    runtime = AgentRuntime.discover()
    decision = asyncio.run(
        runtime.decide(text, role=role, deps=RuntimeDeps(provider=FakeLLMProvider()))
    )
    return decision.business or ""


def test_task_question_goes_to_query_not_question():
    """原 tasks 抬 priority 到 10 就为抢这句；query 用 12 接住。"""
    assert _route("查看我的任务题目", "parent") == "query"
    assert _route("我的错题本里有哪些题", "parent") == "query"


def test_question_intent_still_goes_to_question():
    assert _route("帮我出 3 道三年级分数选择题", "parent") == "question"
    assert _route("来几道数学题练练", "parent") == "question"


def test_tutor_intent_unaffected():
    assert _route("为什么天空是蓝色的？帮我讲解", "parent") == "tutor"


def test_child_out_of_scope_stays_tutor():
    """娃娃问「出题」依旧被角色可见性拦到 tutor（ADR-0026 不变量未破）。"""
    assert _route("帮我出几道数学题", "child") == "tutor"
    assert _route("今天有什么作业", "child") == "query"


# ───────────────────────── 3. 展示投影 ─────────────────────────


def _envelope(items: list[Any]) -> dict[str, Any]:
    return {
        "children": [{"id": "c1", "name": "小明", "grade": 2, "items": items, "meta": {}}],
        "unassigned_items": [],
        "total_children": 1,
        "total_items": len(items),
    }


def test_render_cards_match_frontend_tile_shape():
    cards = render_cards(
        "list_wrong_questions",
        _envelope(
            [
                {
                    "subject": "数学",
                    "stem": "9 + 3 = ?",
                    "wrong_count": 2,
                    "answer": "12",
                    "explanation": "进位。",
                }
            ]
        ),
    )
    assert len(cards) == 1
    card = cards[0]
    assert set(card) == {"type", "subject", "stem"}  # 前端 _CardTile 消费契约
    assert card["type"] == "错题"
    assert card["subject"] == "小明（2年级）"
    assert "9 + 3" in card["stem"] and "错 2 次" in card["stem"]


def test_render_cards_handles_empty_error_tools_and_caps_lines():
    empty = render_cards("list_today_tasks", _envelope([]))
    assert empty[0]["stem"] == "今天没有任务。"

    err = render_cards("get_progress", {"error": "没有找到该娃娃。"})
    assert err == [{"type": "学习进度", "subject": "", "stem": "查询失败：没有找到该娃娃。"}]

    many = render_cards("list_due_reviews", _envelope([{"stem": f"题 {i}"} for i in range(12)]))
    assert "共 12 条" in many[0]["stem"]

    assert render_cards("list_children", _envelope([]))[0]["stem"] == "可查询的娃娃"


def test_render_tool_result_emits_data_frames():
    agent = QuerySubAgent(provider=FakeLLMProvider())
    frames = agent.render_tool_result(
        "get_progress",
        _envelope([{"total": 4, "correct": 3, "accuracy": 0.75, "streak_days": 2}]),
    )
    assert [f.eventType for f in frames] == [EVENT_DATA]
    assert frames[0].data["type"] == "query"
    assert "答对 3/4" in frames[0].data["result"]["stem"]
    # 基类默认不产帧 → 出题/伴学不受影响（回归护栏）
    assert TutorSubAgent(provider=FakeLLMProvider()).render_tool_result("x", {}) == []


# ───────────────────────── 4. 端到端 tool loop（真 DB） ─────────────────────────


class _ScriptedProvider(FakeLLMProvider):
    """确定性脚本：首轮请求指定工具，回灌后给收尾文本（表达不了多跳就是它该管的范围）。"""

    def __init__(self, tool_name: str, args: dict[str, Any] | None = None) -> None:
        self.tool_name = tool_name
        self.args = args or {}
        self.requests = 0

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if tools and not history:
            self.requests += 1
            yield ToolCall(name=self.tool_name, args=self.args)
            return
        yield TextDelta(delta="已查到结果。")


def _drive(agent: QuerySubAgent, ctx: SubAgentContext) -> list[Any]:
    async def _go() -> list[Any]:
        with Session(engine) as session:
            return [
                ev
                async for ev in run_with_tools(agent, "随便问", ctx, session=session)
            ]

    return asyncio.run(_go())


def _payloads(events: list[Any], event_type: str) -> str:
    return json.dumps(
        [ev.result if event_type == EVENT_TOOL_RESULT else ev.data for ev in events
         if ev.eventType == event_type],
        ensure_ascii=False,
        default=str,
    )


def test_tool_loop_emits_full_event_chain(client):
    setup = _setup(client, "qs")
    ctx = SubAgentContext(role="parent", extra={"parent_id": setup["parent_id"]})
    provider = _ScriptedProvider("list_children")
    events = _drive(QuerySubAgent(provider=provider), ctx)

    types = [ev.eventType for ev in events]
    assert EVENT_TOOL_CALL in types and EVENT_TOOL_RESULT in types
    assert EVENT_DATA in types and EVENT_ASSISTANT_MESSAGE in types
    assert provider.requests == 1  # 回灌后进入收尾轮，不重复请求工具
    # DATA 帧在 TOOL_RESULT 之后（决策 11 的「后发展示卡」顺序）
    assert types.index(EVENT_TOOL_RESULT) < types.index(EVENT_DATA)


def test_child_frames_never_carry_answers_and_parent_control_does(client):
    """ADR-008 硬门槛在**帧层**再守一道（工具层已由契约测试守）。"""
    setup = _setup(client, "qa")
    tool = "list_wrong_questions"

    child_ctx = SubAgentContext(
        role="child",
        extra={"child_id": setup["a"]["id"], "parent_id": setup["parent_id"]},
    )
    child_events = _drive(QuerySubAgent(provider=_ScriptedProvider(tool)), child_ctx)
    child_text = _payloads(child_events, EVENT_TOOL_RESULT) + _payloads(child_events, EVENT_DATA)
    assert "错题" in child_text, "娃娃端没查到错题 → 断言失去意义（假绿）"
    for field in ANSWER_FIELDS:
        assert field not in child_text, f"娃娃端帧里泄漏了 {field}"

    parent_ctx = SubAgentContext(
        role="parent",
        extra={"parent_id": setup["parent_id"], "child_id": setup["a"]["id"]},
    )
    parent_events = _drive(QuerySubAgent(provider=_ScriptedProvider(tool)), parent_ctx)
    parent_text = _payloads(parent_events, EVENT_TOOL_RESULT)
    assert '"answer"' in parent_text, "家长对照组拿不到答案 → 上一条断言可能是假绿"


def test_run_degrades_explicitly_when_tools_missing():
    """``run`` 兜底路径：装配异常（tools 空）必须显式报不可用，不静默退化成纯聊天。"""
    agent = QuerySubAgent(provider=FakeLLMProvider())
    agent.tools = []
    ctx = SubAgentContext(role="parent", extra={"parent_id": "x"})

    async def _go() -> list[Any]:
        return [ev async for ev in agent.run("我的任务", ctx)]

    events = asyncio.run(_go())
    assert [e.eventType for e in events] == [EVENT_ASSISTANT_MESSAGE]
    assert events[0].blocked is True
