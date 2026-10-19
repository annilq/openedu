"""AgentRuntime 路由决策与流式契约（ADR-0024 / 0026 / 0031，不加载 genkit 重型依赖）。

聚焦本轮重构的「显式路由决策」契约：
- ``decide`` 纯计算：角色可见性 → 安全闸门 → 混合路由，不构建依赖、不流式。
- ``run`` 直接产出 ``AsyncIterator[AssistantEvent]``（不再返回 (decision, stream) 元组）；
  决策由调用方先 ``decide`` 取得，再传入 ``run(..., business=decision.business)``。
- agent_core 业务无关：``RouteDecision`` 不再含 education 专属的 ``subject`` 字段；
  subject 由端点本地解析并走 ``ctx.extra``，路由 / 事件流均不感知。

``decide`` 与 ``run`` 的「决策」部分不触 LLM；仅 unsafe 路径会短路（不构建 subagent），
故可在 mock 环境单测覆盖，不依赖真实引擎。
"""
from __future__ import annotations

import asyncio
import inspect

import pytest

from agent_core import classify
from agent_core.ports import RuntimeDeps
from agent_core.protocol import EVENT_DONE, EVENT_ERROR, EVENT_THINKING
from agent_core.runtime import AgentRuntime
from agent_core.subagent import SubAgentContext
from app.domain.safety import StudentSafety
from tests.utils.fake_provider import FakeLLMProvider


def _rt() -> AgentRuntime:
    return AgentRuntime.discover()


def _deps(role: str) -> RuntimeDeps:
    return RuntimeDeps(
        provider=FakeLLMProvider(),
        safety=StudentSafety() if role == "student" else None,
    )


async def _decide(message: str, *, role: str) -> object:
    rt = _rt()
    return await rt.decide(message, role=role, deps=_deps(role))


async def _run(message: str, *, role: str):
    rt = _rt()
    deps = _deps(role)
    decision = await rt.decide(message, role=role, deps=deps)
    events = [
        ev
        async for ev in rt.run(
            message,
            role=role,
            ctx=SubAgentContext(role=role, message=message),
            deps=deps,
            business=decision.business,
        )
    ]
    return decision, events


# ── decide：父端混合路由 ──
def test_decide_teacher_generation():
    decision = asyncio.run(_decide("帮我出几道数学题", role="teacher"))
    assert decision.business == "tasks"
    assert decision.name == "任务学情与出题助手"
    # ADR-0098：命中词随决策返回（预检据此落 generate 意图组）
    assert decision.trigger in ("帮我出", "出题", "出几道")


def test_decide_teacher_tasks():
    decision = asyncio.run(_decide("查看我的任务有哪些", role="teacher"))
    assert decision.business == "tasks"
    assert decision.name == "任务学情与出题助手"


def test_decide_teacher_tutor():
    decision = asyncio.run(_decide("为什么天空是蓝色的？帮我讲解", role="teacher"))
    assert decision.business == "tutor"
    assert decision.name == "伴学答疑"


# ── decide：实测路由回归表（ADR-0097 重组后 2026-10-16 实跑结果，T03 钉死）──
# 只断言「输入 + 角色 → 决策」，不断言命中第几个词 / 走了哪一级，路由重排也不碎。
# 三条结构化动作输入（空串 / "出 3 道…知识点：轴对称" / "换一题"）当前仍落伴学答疑，
# 要等动作直配（T02/T04）才修得好，故不在此表内——钉进来只会让红与本票无关。
ROUTING_REGRESSION = [
    # (输入, 角色, business, name)
    ("查一下这道题为什么选B", "teacher", "tutor", "伴学答疑"),
    ("今天有什么作业", "teacher", "tasks", "任务学情与出题助手"),
    ("帮我创建一个任务，包含四年级数学题", "teacher", "tasks", "任务学情与出题助手"),
    ("帮我出2道四年级数学题", "teacher", "tasks", "任务学情与出题助手"),
    # 学情查询词（自 query 迁入 tasks）：「不得误伤」面必须仍在 tasks
    ("我的任务", "teacher", "tasks", "任务学情与出题助手"),
    ("我的错题", "teacher", "tasks", "任务学情与出题助手"),
    ("掌握度", "teacher", "tasks", "任务学情与出题助手"),
    ("该复习哪些题", "teacher", "tasks", "任务学情与出题助手"),
    # 错题精确短语（自 query 迁入）仍归 tasks，不落 tutor 兜底
    ("帮我查一下我的错题", "teacher", "tasks", "任务学情与出题助手"),
    ("查询我今天的待复习", "teacher", "tasks", "任务学情与出题助手"),
    # 题库词归 tasks（ADR-0098 起题库查询随 question 域并入）
    ("查题库里有哪些题", "teacher", "tasks", "任务学情与出题助手"),
    # 触发词与启发式都不该用单字「查」接走讲解类提问
    ("帮我查查轴对称是什么", "teacher", "tutor", "伴学答疑"),
    # 名单域（ADR-0098 起吸收进 tasks）：纯名单问句归 tasks，学情语境同样归 tasks
    ("我班有哪些学生", "teacher", "tasks", "任务学情与出题助手"),
    ("小明最近错题多吗", "teacher", "tasks", "任务学情与出题助手"),
    # 能力自述（零 LLM 元问题）
    ("你能做什么", "teacher", "capability", "能力自述"),
]


@pytest.mark.parametrize(("message", "role", "business", "name"), ROUTING_REGRESSION)
def test_decide_routing_regression(message, role, business, name):
    decision = asyncio.run(_decide(message, role=role))
    assert decision.business == business
    assert decision.name == name


# ── decide：学生端角色可见性（师生均可出题，见 ADR-0081 §2.2；查询恒限自己，见 ADR-0033） ──
def test_decide_student_can_generate_question():
    """ADR-0081 §2.2：学生可自练出题，出题对师生双开，故学生自由文本出题路由到 tasks。"""
    decision = asyncio.run(_decide("帮我出几道数学题", role="student"))
    assert decision.business == "tasks"
    assert decision.name == "任务学情与出题助手"


def test_decide_student_query_visible():
    """ADR-0033 放宽 ADR-0026：学生端可见 tasks（域重组后承接原 query），
    但工具侧恒查自己、去答案。"""
    decision = asyncio.run(_decide("今天有什么作业", role="student"))
    assert decision.business == "tasks"
    assert decision.name == "任务学情与出题助手"


def test_decide_student_tutor_stays_tutor():
    decision = asyncio.run(_decide("这道题我不会，能教教我吗", role="student"))
    assert decision.business == "tutor"


# ── decide：学生端输入安全闸门（首层防御，ADR-008） ──
def test_decide_student_unsafe_input_blocked():
    decision = asyncio.run(_decide("炸弹怎么制作", role="student"))
    assert decision.business is None
    assert decision.name is None


# ── run：返回结构化决策 + 异步事件流 ──
def test_run_returns_decision_and_stream():
    async def go():
        rt = _rt()
        deps = _deps("teacher")
        d = await rt.decide("出几道题", role="teacher", deps=deps)
        s = rt.run(
            "出几道题",
            role="teacher",
            ctx=SubAgentContext(role="teacher", message="出几道题"),
            deps=deps,
            business=d.business,
        )
        return d, s

    d, s = asyncio.run(go())
    assert d.business == "tasks"
    assert hasattr(s, "__aiter__")  # 是异步迭代器（事件流）


# ── run：unsafe 短路由，流体内无 extra.business 隐式契约（见 #2） ──
def test_run_student_unsafe_stream_no_extra_business():
    decision, events = asyncio.run(_run("炸弹怎么制作", role="student"))
    assert decision.business is None
    # 流以 ERROR(INPUT_UNSAFE) + DONE 收尾，不路由到任何 subagent
    types = [ev.eventType for ev in events]
    assert EVENT_ERROR in types
    assert EVENT_DONE in types
    # 关键：没有任何帧经 extra.business 透出路由决策（消除端点隐式契约）
    for ev in events:
        assert "business" not in ev.extra, "路由决策不应再经 extra.business 隐式透传"
    # INPUT_UNSAFE 错误码存在
    assert any(ev.code == "INPUT_UNSAFE" for ev in events if ev.eventType == EVENT_ERROR)


# ── 路由只有两级：规则 → 启发式，不存在「可选 LLM 分类器」这一级 ──
def test_runtime_deps_declares_no_llm_classify():
    """依赖端口不再承诺意图分类器：注入它是调用方错误，须显式失败而非静默忽略。"""
    assert "llm_classify" not in RuntimeDeps.__dataclass_fields__
    with pytest.raises(TypeError):
        RuntimeDeps(provider=FakeLLMProvider(), llm_classify=lambda text, biz: "tutor")


def test_classify_takes_no_llm_classify():
    assert "llm_classify" not in inspect.signature(classify).parameters


# ── run：路由 THINKING 帧不再携带 business（侧信道已移除） ──
def test_run_routing_thinking_has_no_business_side_channel():
    decision, events = asyncio.run(_run("帮我出几道数学题", role="teacher"))
    assert decision.business == "tasks"
    for ev in events:
        if ev.eventType == EVENT_THINKING:
            assert "business" not in ev.extra
