"""``tasks`` 任务学情域 SubAgent 契约测试（ADR-0033 决策 6 / 11 / 14 / ADR-0097 按域重组）。

守护四件事，全部**确定性**、不接真实模型（CI 红线）：

1. **清单与装配**：``tasks`` 被发现、``query``/``guide`` 已消失、``priority=14``
   （压住 question 的泛触发词「题目」、接住原 guide 的写意图位）；SubAgent 实例
   携带全部 7 个工具（6 读 + 1 写 create_draft）。
2. **路由边界**：带学情语境的问句（任务/作业/错题/复习）归 ``tasks``，
   「出题」意图仍归 ``question``，纯人群问句归 ``students``；学生端同样可见
   ``tasks``（查自己），「出题」对学生也开放（ADR-0081 §2.2）。
3. **展示投影**（决策 11 / ADR-0042）：卡片是**类型化**的——``kind`` 作判别键、
   载荷是结构化字段（``items`` / ``stats`` / ``total``），不是拼好的展示字符串；
   答案与解析永不进卡片，错误结果不炸流。
4. **端到端 tool loop**：真 DB + 脚本化 provider 跑一轮，``TOOL_CALL`` → ``TOOL_RESULT``
   → ``DATA`` → ``ASSISTANT_MESSAGE`` 齐备；**学生端帧里不出现答案/解析**，教师端对照
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
from app.ai.shared.render import render_cards
from app.ai.shared.tool_support import ANSWER_FIELDS
from app.ai.subagents.tasks import TasksSubAgent
from app.ai.subagents.tasks.tools import TASKS_TOOLS
from app.ai.subagents.tutor import TutorSubAgent
from app.core.db import engine
from tests.ai.test_business_tools_contract import (
    _setup,  # 复用同一套数据装置（1 教师 + 2 学生 + 任务 + 错题 + 未派发草稿）
)
from tests.utils.fake_provider import FakeLLMProvider

# ───────────────────────── 1. 清单与装配 ─────────────────────────


def test_manifest_declares_tasks_domain():
    manifests = discover_subagent_manifests()
    assert "tasks" in manifests
    # ADR-0097：query 解散、guide 删除——两者的位置由 tasks 接任
    assert "query" not in manifests and "guide" not in manifests
    m = manifests["tasks"]
    assert (m.business, m.name) == ("tasks", "任务学情助手")
    assert m.roles == ["teacher", "student"]
    # 高于 question(12) 才能压住泛词「题目」；写意图短语接原 guide(20) 的拦截位
    assert m.priority == 14
    # 无 skills：SOP 纪律已并入 system prompt（原 query_sop 的核心约束逐条在内）
    assert m.skills == []


def test_agent_carries_all_tasks_tools():
    agent = build_subagent(discover_subagent_manifests(), "tasks", provider=FakeLLMProvider())
    assert isinstance(agent, TasksSubAgent)
    assert [t.name for t in agent.tools] == [
        "list_teacher_tasks",
        "list_today_tasks",
        "list_wrong_questions",
        "get_progress",
        "list_due_reviews",
        "get_mastery",
        "create_draft",
    ]
    assert [t.name for t in TASKS_TOOLS] == [t.name for t in agent.tools]
    assert agent.max_turns == 3  # 内默认：查询 1–2 跳足够


def test_initial_system_carries_role_hint():
    agent = TasksSubAgent(provider=FakeLLMProvider())
    student = agent.initial_system("今天有什么作业", SubAgentContext(role="student", skills="SOP-X"))
    teacher = agent.initial_system("学生错题", SubAgentContext(role="teacher", skills="SOP-X"))
    assert "学生本人" in student and "学生本人" not in teacher
    assert "教师" in teacher
    assert student.endswith("SOP-X") and teacher.endswith("SOP-X")


def test_initial_system_injects_kp_focus_segment():
    """ADR-0080：带焦点知识点时系统提示含【知识点聚焦】段，且额外强调须依托工具数据。"""
    agent = TasksSubAgent(provider=FakeLLMProvider())
    focused = agent.initial_system(
        "轴对称是什么意思",
        SubAgentContext(
            role="student",
            extra={"knowledge_point": {"subject": "数学", "grade": 5, "semester": "上学期", "name": "轴对称"}},
        ),
    )
    assert "【知识点聚焦】" in focused
    assert "轴对称" in focused
    assert "查询仍须依托工具数据" in focused


def test_initial_system_no_kp_focus_without_extra():
    """无焦点知识点时不注入该段（无回归，requires_tool_data 契约不变）。"""
    agent = TasksSubAgent(provider=FakeLLMProvider())
    plain = agent.initial_system("今天有什么作业", SubAgentContext(role="student"))
    assert "【知识点聚焦】" not in plain
    assert "查询仍须依托工具数据" not in plain


# ───────────────────────── 2. 路由边界 ─────────────────────────


def _route(text: str, role: str) -> str:
    runtime = AgentRuntime.discover()
    decision = asyncio.run(
        runtime.decide(text, role=role, deps=RuntimeDeps(provider=FakeLLMProvider()))
    )
    return decision.business or ""


def test_task_question_goes_to_tasks_not_question():
    """question 的 triggers 含泛词「题目」，tasks 用 priority=14 压住它。"""
    assert _route("查看我的任务题目", "teacher") == "tasks"
    assert _route("我的错题本里有哪些题", "teacher") == "tasks"


def test_question_intent_still_goes_to_question():
    assert _route("帮我出 3 道三年级分数选择题", "teacher") == "question"
    assert _route("来几道数学题练练", "teacher") == "question"


def test_students_intent_goes_to_students():
    """人群域边界：纯名单问句归 students，带学情语境的仍归 tasks。"""
    assert _route("我班有哪些学生", "teacher") == "students"
    assert _route("小明最近错题多吗", "teacher") == "tasks"


def test_tutor_intent_unaffected():
    assert _route("为什么天空是蓝色的？帮我讲解", "teacher") == "tutor"


def test_wrong_question_phrasing_goes_to_tasks_not_tutor():
    """回归（2026-09-22）：『我错了哪些题』原落 tutor 兜底（无取数工具，让用户发题目），

    现已在 tasks triggers 覆盖——只加带『哪些/错过』的精确短语，不抢伴学答疑。"""
    assert _route("我错了哪些题", "teacher") == "tasks"
    assert _route("我错过的题", "teacher") == "tasks"
    assert _route("做错了哪些题", "teacher") == "tasks"
    # 伴学答疑句仍归 tutor，不被新词抢走（ADR-0024/0030）
    assert _route("这道题我哪里做错了，为什么", "teacher") == "tutor"
    assert _route("为什么天空是蓝色的？帮我讲解", "teacher") == "tutor"
    # 学生端同样归 tasks（查自己错题，ADR-008），不被角色拦回 tutor
    assert _route("我错了哪些题", "student") == "tasks"


def test_student_generation_routes_to_question():
    """学生自练出题：出题助手对师生双开（ADR-0081 §2.2），故学生出题意图路由到 question。"""
    assert _route("帮我出几道数学题", "student") == "question"
    assert _route("今天有什么作业", "student") == "tasks"


# ───────────────────────── 3. 展示投影 ─────────────────────────


def _envelope(items: list[Any]) -> dict[str, Any]:
    return {
        "students": [{"id": "c1", "name": "小明", "grade": 2, "items": items, "meta": {}}],
        "unassigned_items": [],
        "total_students": 1,
        "total_items": len(items),
    }


def test_render_cards_are_typed_and_structured():
    """卡片 = 判别键（kind）+ 结构化载荷；答案/解析永不进卡片（ADR-0042）。"""
    cards = render_cards(
        "list_wrong_questions",
        _envelope(
            [
                {
                    "subject": "数学",
                    "stem": "9 + 3 = ?",
                    "qtype": "calc",
                    "wrong_count": 2,
                    "answer": "12",
                    "explanation": "进位。",
                }
            ]
        ),
    )
    assert len(cards) == 1
    card = cards[0]
    assert card.kind == "wrong_question_list"
    assert card.payload["title"] == "错题"
    assert card.payload["subject"] == "小明（2年级）"
    assert card.payload["total"] == 1
    # 明细是字段，不是拼好的一行文本——前端据此排版（题干 + 「错过 N 次」标签）。
    assert card.payload["items"] == [
        {"subject": "数学", "stem": "9 + 3 = ?", "qtype": "calc", "wrong_count": 2}
    ]
    dumped = json.dumps(card.payload, ensure_ascii=False)
    assert "answer" not in card.payload["items"][0]
    assert "进位" not in dumped  # 解析正文也不进卡片


def test_render_cards_handles_empty_error_tools_and_caps_items():
    empty = render_cards("list_today_tasks", _envelope([]))
    assert empty[0].kind == "task_list"
    assert empty[0].payload["text"] == "今天没有任务。"
    assert "items" not in empty[0].payload  # 没明细就不发空数组

    err = render_cards("get_progress", {"error": "没有找到该学生。"})
    assert err[0].kind == "notice"
    assert err[0].payload["text"] == "查询失败：没有找到该学生。"

    many = render_cards("list_due_reviews", _envelope([{"stem": f"题 {i}"} for i in range(12)]))
    capped = many[0]
    assert len(capped.payload["items"]) == 5  # 明细截断
    assert capped.payload["total"] == 12  # 但如实报总数（前端渲染「共 12 条」）
    assert capped.payload["items"][0]["stem"] == "题 0"

    students = render_cards("list_students", _envelope([]))
    assert students[0].kind == "student_list"
    assert students[0].payload["text"] == "可查询的学生"


def test_render_cards_progress_uses_stats_not_items():
    """进度是单条聚合：走 stats，别塞进 items（前端据此选指标卡版式）。"""
    cards = render_cards(
        "get_progress",
        _envelope([{"total": 4, "correct": 3, "accuracy": 0.75, "streak_days": 2, "checkin_days": 5}]),
    )
    assert cards[0].kind == "progress"
    assert cards[0].payload["stats"] == {
        "total": 4,
        "correct": 3,
        "accuracy": 0.75,
        "streak_days": 2,
        "checkin_days": 5,
    }
    assert "items" not in cards[0].payload


def test_render_cards_unassigned_items_keep_structure():
    """未指派草稿走同一套结构化明细，只是归属标签不同。"""
    result = {
        "students": [],
        "unassigned_items": [{"title": "草稿卷", "status": "draft", "questions": [{}, {}]}],
    }
    cards = render_cards("list_teacher_tasks", result)
    assert cards[0].payload["title"] == "任务·未指派"
    assert cards[0].payload["subject"] == "未指派"
    assert cards[0].payload["items"] == [
        {"title": "草稿卷", "status": "draft", "question_count": 2}
    ]


def test_render_cards_bank_questions_emits_question_bank_list():
    """题库题目 → ``question_bank_list`` 卡片，明细是结构化字段（该工具已归 question 域）。"""
    cards = render_cards(
        "list_bank_questions",
        _envelope(
            [
                {
                    "id": "q1",
                    "subject": "数学",
                    "stem": "解方程 x^2 - 1 = 0",
                    "knowledge_point": "一元二次方程",
                    "qtype": "calc",
                    "difficulty": 3,
                    "usage_count": 2,
                }
            ]
        ),
    )
    assert len(cards) == 1
    card = cards[0]
    assert card.kind == "question_bank_list"
    assert card.payload["title"] == "题库"
    assert card.payload["total"] == 1
    assert card.payload["items"] == [
        {
            "id": "q1",
            "subject": "数学",
            "stem": "解方程 x^2 - 1 = 0",
            "knowledge_point": "一元二次方程",
            "qtype": "calc",
            "difficulty": 3,
            "usage_count": 2,
        }
    ]


def test_render_cards_bank_questions_empty_uses_bank_empty_text():
    """题库为空时落到专属空文案（区分「查过但没题」与「没查」）。"""
    cards = render_cards("list_bank_questions", _envelope([]))
    assert cards[0].kind == "question_bank_list"
    assert cards[0].payload["text"] == "题库还没有题目。"


def test_render_tool_result_emits_typed_data_frames():
    agent = TasksSubAgent(provider=FakeLLMProvider())
    frames = agent.render_tool_result(
        "get_progress",
        _envelope([{"total": 4, "correct": 3, "accuracy": 0.75, "streak_days": 2}]),
    )
    assert [f.eventType for f in frames] == [EVENT_DATA]
    # 种类进信封 data.type（前端分派键），载荷进 data.result。
    assert frames[0].data["type"] == "progress"
    assert frames[0].data["result"]["stats"]["correct"] == 3
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


def _drive(agent: TasksSubAgent, ctx: SubAgentContext) -> list[Any]:
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
    ctx = SubAgentContext(role="teacher", extra={"teacher_id": setup["teacher_id"]})
    provider = _ScriptedProvider("list_teacher_tasks")
    events = _drive(TasksSubAgent(provider=provider), ctx)

    types = [ev.eventType for ev in events]
    assert EVENT_TOOL_CALL in types and EVENT_TOOL_RESULT in types
    assert EVENT_DATA in types and EVENT_ASSISTANT_MESSAGE in types
    assert provider.requests == 1  # 回灌后进入收尾轮，不重复请求工具
    # DATA 帧在 TOOL_RESULT 之后（决策 11 的「后发展示卡」顺序）
    assert types.index(EVENT_TOOL_RESULT) < types.index(EVENT_DATA)


def test_student_frames_never_carry_answers_and_teacher_control_does(client):
    """ADR-008 硬门槛在**帧层**再守一道（工具层已由契约测试守）。"""
    setup = _setup(client, "qa")
    tool = "list_wrong_questions"

    student_ctx = SubAgentContext(
        role="student",
        extra={"student_id": setup["a"]["id"], "teacher_id": setup["teacher_id"]},
    )
    student_events = _drive(TasksSubAgent(provider=_ScriptedProvider(tool)), student_ctx)
    student_text = _payloads(student_events, EVENT_TOOL_RESULT) + _payloads(student_events, EVENT_DATA)
    assert "错题" in student_text, "学生端没查到错题 → 断言失去意义（假绿）"
    for field in ANSWER_FIELDS:
        assert field not in student_text, f"学生端帧里泄漏了 {field}"

    teacher_ctx = SubAgentContext(
        role="teacher",
        extra={"teacher_id": setup["teacher_id"], "student_id": setup["a"]["id"]},
    )
    teacher_events = _drive(TasksSubAgent(provider=_ScriptedProvider(tool)), teacher_ctx)
    teacher_text = _payloads(teacher_events, EVENT_TOOL_RESULT)
    assert '"answer"' in teacher_text, "教师对照组拿不到答案 → 上一条断言可能是假绿"


def test_run_degrades_explicitly_when_tools_missing():
    """``run`` 兜底路径：装配异常（tools 空）必须显式报不可用，不静默退化成纯聊天。"""
    agent = TasksSubAgent(provider=FakeLLMProvider())
    agent.tools = []
    ctx = SubAgentContext(role="teacher", extra={"teacher_id": "x"})

    async def _go() -> list[Any]:
        return [ev async for ev in agent.run("我的任务", ctx)]

    events = asyncio.run(_go())
    assert [e.eventType for e in events] == [EVENT_ASSISTANT_MESSAGE]
    assert events[0].blocked is True
