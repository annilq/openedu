"""``students`` 人群域 SubAgent 契约测试（ADR-0097）。

单工具 agent 的存在理由是**路由边界**（见 students/agent.py 文档串），本文件守住：

1. **清单与装配**：``students`` 被发现、``priority=10``（低于 tasks 14，聚合学情问题
   不被名单域断掉）、双端可见、无槽位（名单查询无参数）。
2. **路由边界**：纯人群问句归 ``students``；带学情语境的（错题/进度）归 ``tasks``；
   「出题」仍归 ``question``；伴学句归 ``tutor``。
3. **端到端 tool loop**：真 DB + 脚本化 provider 跑一轮事件链齐备；学生端只看到自己。
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
from app.ai.subagents.students import StudentsSubAgent
from app.ai.subagents.students.tools import STUDENTS_TOOLS
from app.core.db import engine
from tests.ai.test_business_tools_contract import _setup
from tests.utils.fake_provider import FakeLLMProvider


# ───────────────────────── 1. 清单与装配 ─────────────────────────


def test_manifest_declares_students_domain():
    m = discover_subagent_manifests()["students"]
    assert (m.business, m.name) == ("students", "学生名单助手")
    assert m.roles == ["teacher", "student"]
    # 低于 tasks(14)：聚合学情问题（「小明最近错题多吗」）必须落 tasks
    assert m.priority == 10
    # 名单查询无参数 → 无槽位（input_schema 经 manifest.raw 承载，ADR-0095）
    assert m.raw.get("input_schema") == []


def test_agent_carries_single_tool():
    agent = build_subagent(
        discover_subagent_manifests(), "students", provider=FakeLLMProvider()
    )
    assert isinstance(agent, StudentsSubAgent)
    assert [t.name for t in agent.tools] == ["list_students"]
    assert [t.name for t in STUDENTS_TOOLS] == ["list_students"]


# ───────────────────────── 2. 路由边界 ─────────────────────────


def _route(text: str, role: str) -> str:
    runtime = AgentRuntime.discover()
    decision = asyncio.run(
        runtime.decide(text, role=role, deps=RuntimeDeps(provider=FakeLLMProvider()))
    )
    return decision.business or ""


def test_roster_intent_goes_to_students():
    assert _route("我班有哪些学生", "teacher") == "students"
    assert _route("班里孩子们名单", "teacher") == "students"
    assert _route("我名下有几个娃", "teacher") == "students"


def test_academic_context_stays_in_tasks():
    """带学情语境的问句归 tasks——那边工具更全，聚合问题不应在名单域断掉。"""
    assert _route("小明最近错题多吗", "teacher") == "tasks"
    assert _route("看看学生们的学习进度", "teacher") == "tasks"


def test_question_and_tutor_intent_unaffected():
    assert _route("帮我出几道数学题", "teacher") == "question"
    assert _route("为什么天空是蓝色的", "teacher") == "tutor"


# ───────────────────────── 3. 端到端 tool loop（真 DB） ─────────────────────────


class _ScriptedProvider(FakeLLMProvider):
    """确定性脚本：首轮请求 list_students，回灌后给收尾文本。"""

    def __init__(self) -> None:
        self.requests = 0

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if tools and not history:
            self.requests += 1
            yield ToolCall(name="list_students", args={})
            return
        yield TextDelta(delta="以上就是名单。")


def _drive(agent: StudentsSubAgent, ctx: SubAgentContext) -> list[Any]:
    async def _go() -> list[Any]:
        with Session(engine) as session:
            return [
                ev
                async for ev in run_with_tools(agent, "我班有哪些学生", ctx, session=session)
            ]

    return asyncio.run(_go())


def test_tool_loop_emits_full_event_chain(client):
    setup = _setup(client, "st")
    ctx = SubAgentContext(role="teacher", extra={"teacher_id": setup["teacher_id"]})
    provider = _ScriptedProvider()
    events = _drive(StudentsSubAgent(provider=provider), ctx)

    types = [ev.eventType for ev in events]
    assert EVENT_TOOL_CALL in types and EVENT_TOOL_RESULT in types
    assert EVENT_DATA in types and EVENT_ASSISTANT_MESSAGE in types
    assert provider.requests == 1
    # 名单卡是类型化的（student_list），不是拼好的文本
    data = [ev for ev in events if ev.eventType == EVENT_DATA]
    assert data[0].data["type"] == "student_list"


def test_student_only_sees_self(client):
    """学生端跑 list_students：恒为自己，不出现兄弟学生。"""
    setup = _setup(client, "st_self")
    ctx = SubAgentContext(
        role="student",
        extra={"student_id": setup["a"]["id"], "teacher_id": setup["teacher_id"]},
    )
    events = _drive(StudentsSubAgent(provider=_ScriptedProvider()), ctx)
    blob = json.dumps(
        [ev.data for ev in events if ev.eventType == EVENT_DATA],
        ensure_ascii=False,
        default=str,
    )
    assert "小明" in blob, "学生端没拿到自己 → 断言失去意义（假绿）"
    assert "小红" not in blob, "学生端泄漏了兄弟学生"
