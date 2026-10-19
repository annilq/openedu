"""tasks 域写意图契约测试（ADR-0097 §2.3：AI 只起草 + 会话内确认卡发布）。

**真机报障（2026-09-17，guide 时代）**：教师说「帮我创建一个任务，包含四年级数学题」，
得到的是「我这边只能查询学习数据，不能生成或派发任务…请到『任务/作业』相关页面操作」。

guide 删除后（ADR-0097），写意图的出口从「固定话术引导到页面」变为
**create_draft 建草稿 + 会话内确认卡**：确认/派发由用户点卡上按钮完成（前端直走
REST ``POST /tasks/{id}/confirm`` + ``/assign``），发布决定权与任务页按钮同权。
本文件守住四件事（全部确定性，不接真实模型）：

1. **路由**：写意图（「创建任务」类完整短语）归 ``tasks``；查询意图不被写短语误抢；
   ``question`` / ``tutor`` 意图不受影响；学生端**可见** tasks（查自己），但写工具
   在 handler 内按角色拒绝（不靠隐藏业务来「保护」）。
2. **必填校验**：未指名目标学生 → ``ToolArgumentError`` 回灌（模型转问），
   不擅自建任务；昵称命中多人 → 同样回灌要求指明。
3. **只起草**：建出来是 ``draft`` 态任务、未派发；确认卡以
   ``task_draft_card`` DATA 帧下发（ADR-0042 类型化卡片）。
4. **端到端 tool loop**：真 DB + 脚本化 provider 跑一轮，事件链齐备且卡载荷含
   ``task_id``；库里任务确为 draft。
"""
from __future__ import annotations

import asyncio
import json
from typing import Any
from uuid import UUID

import pytest
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
from app.ai.shared.tool_support import ToolArgumentError
from app.ai.subagents.tasks import TasksSubAgent
from app.ai.subagents.tasks.tools import TASKS_TOOLS
from app.ai.subagents.tasks.tools.create_draft import draft_card
from app.core.db import engine
from app.db.models import Question, Task
from tests.ai.test_business_tools_contract import _setup
from tests.utils.fake_provider import FakeLLMProvider


def _spec(name: str):
    for spec in TASKS_TOOLS:
        if spec.name == name:
            return spec
    raise AssertionError(f"tasks 域未注册的工具：{name}")


def _route(text: str, role: str) -> str:
    runtime = AgentRuntime.discover()
    decision = asyncio.run(
        runtime.decide(text, role=role, deps=RuntimeDeps(provider=FakeLLMProvider()))
    )
    return decision.business or ""


def _ctx(role: str, **extra: Any) -> SubAgentContext:
    return SubAgentContext(role=role, extra=extra)


def _run(spec, ctx: SubAgentContext, args: dict[str, Any] | None = None) -> Any:
    """在真实 session 上同步驱动 async handler（工具契约就是「同步直调 DB」）。"""
    with Session(engine) as session:
        return asyncio.run(spec.handler(args or {}, ctx=ctx, session=session))


def _seed_bank(session: Session, teacher_id: str, *, count: int = 2) -> list[UUID]:
    """直接插题库题（题库无 REST 创建端点，题目只由出题生成——测试自建行）。"""
    ids: list[UUID] = []
    for i in range(count):
        q = Question(
            teacher_id=UUID(teacher_id),
            subject="数学",
            grade=2,
            knowledge_point="加法",
            qtype="calc",
            stem=f"题库题 {i}",
            answer=f"ans{i}",
            explanation=f"解析 {i}",
        )
        session.add(q)
        session.commit()
        ids.append(q.id)
    return ids


# ───────────────────────── 1. 路由边界 ─────────────────────────


def test_write_intent_routes_to_tasks():
    """真机报障原句——guide 时代它路由到只读查询，现在归 tasks 的写短语接住。"""
    assert _route("帮我创建一个任务，包含四年级数学题", "teacher") == "tasks"
    assert _route("创建一个任务", "teacher") == "tasks"
    assert _route("帮我建个作业，放2道四年级数学题", "teacher") == "tasks"


def test_read_intent_not_stolen_by_write_phrases():
    """写短语只收「动作+对象」完整短语：查询意图同域着陆，但不触发起草。"""
    assert _route("查一下我创建过的任务", "teacher") == "tasks"
    assert _route("今天有什么作业", "teacher") == "tasks"
    assert _route("我的错题本里有哪些题", "teacher") == "tasks"


def test_generation_and_tutor_intent_unaffected():
    """ADR-0098：出题意图随 question 域并入 tasks（同学情/写意图同域）；伴学仍归 tutor。"""
    assert _route("帮我出2道四年级数学题", "teacher") == "tasks"
    assert _route("为什么天空是蓝色的？帮我讲解", "teacher") == "tutor"


def test_student_sees_tasks_but_write_tool_rejects(client):
    """学生端可见 tasks（查自己），但 create_draft 在 handler 入口按角色拒绝。

    与 guide 时代的差别：不再用「业务对学生不可见」藏写能力，而是工具层显式
    拒绝——错误经回灌转成模型的解释，学生得到的是「仅教师可用」的明确答复。
    """
    assert "tasks" in AgentRuntime.discover().visible_businesses("student")
    setup = _setup(client, "wi_role")
    ctx = _ctx("student", student_id=setup["a"]["id"], teacher_id=setup["teacher_id"])
    with pytest.raises(ToolArgumentError, match="仅教师"):
        _run(_spec("create_draft"), ctx, {"student_name": "小明"})


# ───────────────────────── 2. 入参校验（回灌转问，不擅自建任务） ─────────────────────────


def test_missing_target_student_raises_for_model_to_ask(client):
    """未指名目标学生 → ToolArgumentError（回灌后模型转问），不建误派发的任务。"""
    setup = _setup(client, "wi_target")
    ctx = _ctx("teacher", teacher_id=setup["teacher_id"])
    with pytest.raises(ToolArgumentError, match="必须指定目标学生"):
        _run(_spec("create_draft"), ctx, {"subject": "数学"})


def test_ambiguous_student_name_raises(client):
    """昵称命中多人（「小」→ 小明 + 小红）→ 回灌要求指明，不猜一个。"""
    setup = _setup(client, "wi_amb")
    ctx = _ctx("teacher", teacher_id=setup["teacher_id"])
    with pytest.raises(ToolArgumentError, match="命中 2 人"):
        _run(_spec("create_draft"), ctx, {"student_name": "小"})


# ───────────────────────── 3. 只起草 + 确认卡形状 ─────────────────────────


def test_draft_card_is_typed_data_frame():
    frame = draft_card({"task_id": "t1", "title": "小明的练习（2 题）", "students": ["小明"]})
    assert frame.eventType == EVENT_DATA
    assert frame.data["type"] == "task_draft_card"
    assert frame.data["result"]["task_id"] == "t1"


# ───────────────────────── 4. 端到端 tool loop（真 DB） ─────────────────────────


class _ScriptedProvider(FakeLLMProvider):
    """确定性脚本：首轮请求 create_draft，回灌后给收尾文本。"""

    def __init__(self, args: dict[str, Any]) -> None:
        self.args = args
        self.requests = 0

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if tools and not history:
            self.requests += 1
            yield ToolCall(name="create_draft", args=self.args)
            return
        yield TextDelta(delta="已在下方生成草稿，确认后点发布。")


def _drive(agent: TasksSubAgent, ctx: SubAgentContext) -> list[Any]:
    async def _go() -> list[Any]:
        with Session(engine) as session:
            return [
                ev
                async for ev in run_with_tools(
                    agent, "给小明建个2题的数学练习", ctx, session=session
                )
            ]

    return asyncio.run(_go())


def test_tool_loop_creates_draft_and_emits_confirm_card(client):
    setup = _setup(client, "wi_e2e")
    with Session(engine) as session:
        _seed_bank(session, setup["teacher_id"], count=2)

    ctx = _ctx("teacher", teacher_id=setup["teacher_id"])
    provider = _ScriptedProvider({"student_name": "小明", "subject": "数学", "count": 2})
    events = _drive(TasksSubAgent(provider=provider), ctx)

    types = [ev.eventType for ev in events]
    assert EVENT_TOOL_CALL in types and EVENT_TOOL_RESULT in types
    assert EVENT_DATA in types and EVENT_ASSISTANT_MESSAGE in types
    assert provider.requests == 1

    # 确认卡：类型化载荷，task_id 与目标学生在卡上（前端按钮据此直走 REST）
    data = [ev for ev in events if ev.eventType == EVENT_DATA]
    card = data[0].data
    assert card["type"] == "task_draft_card"
    result = card["result"]
    assert result["task_id"] and result["students"] == ["小明"]
    assert result["question_count"] == 2

    # 库里确为 draft 态、未派发（发布由确认卡按钮走 REST 完成）
    with Session(engine) as session:
        task = session.get(Task, UUID(result["task_id"]))
        assert task is not None
        assert task.status == "draft"
        assert str(task.student_id) == setup["a"]["id"]
        # 草稿任务的确认卡文案进不了答案字段（防泄漏面）
        blob = json.dumps(card, ensure_ascii=False)
        assert "ans0" not in blob
