"""ADR-0021 多 Agent 骨架运行时验证（不加载 genkit 重型依赖，可沙箱单测）。

验证 seam 的关键点（均经真实 ``run()`` 入口驱动，与线上悬浮助手同一条路径）：
1. 学科 Persona 归一化 + 未知兜底（通用）；
2. SubAgent 注册表按业务键派发，未知业务返回 None；
3. 出题 SubAgent：RAG 检索接线 + 学科 Persona 注入 user_prompt（ADR-0030 收口 #4 后
   prompt 组装在 SubAgent 内完成，provider 只收 ``system / prompt / schema`` 消息级接口）；
4. 伴学 SubAgent：学科 Persona 注入讲解 context（复用 TutorService.aexplain 真实路径）。

说明：``run()`` 是 async generator，测试用 ``_drive`` 包一层 asyncio.run 收集事件，避免
嵌套事件循环。真实 LLM 调用路径（genkit）需真机 / CI runner 验证。
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass

from agent_core.registry import (
    build_subagent,
    discover_subagent_manifests,
    get_subagent_class,
)
from agent_core.seams import StructuredDone, TextDelta
from agent_core.subagent import SubAgentContext
from app.ai.subagents import get_subject_persona
from app.ai.subagents.question.agent import QuestionSubAgent, expand_specs
from app.ai.subagents.tutor.agent import TutorSubAgent
from app.domain.provider import EducationLLMProvider


@dataclass
class _FakeQuestion:
    stem: str = "stem"
    subject: str = "数学"
    grade: int = 3
    knowledge_point: str = "分数"
    qtype: str = "choice"
    options: list[str] | None = None
    answer: str = "B"
    explanation: str = "x"
    difficulty: str = "medium"


# 最小题面字典：subject/grade 等由 spec 回填，assemble_question 只取题面四要素。
_Q_DICT: dict = {
    "stem": "这是一道测试题的题干。",
    "options": ["A. 一", "B. 二", "C. 三", "D. 四"],
    "answer": "B",
    "explanation": "推导可得。",
}


class _FakeProvider(EducationLLMProvider):
    """实现消息级 ``stream`` + 教育特有 ``tutor``，隔离真实模型。"""

    def __init__(self) -> None:
        self.last_gen_kwargs: dict | None = None
        self.last_tutor_context: str | None = None

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        self.last_gen_kwargs = {"user_prompt": prompt}
        yield TextDelta(delta="思路")
        yield StructuredDone(data=dict(_Q_DICT))

    async def tutor(self, *, grade, subject, knowledge_point, context, question, history=None):
        self.last_tutor_context = context
        return "讲解内容"

    async def grade_open(self, *, question, student_answer) -> dict:
        return {}


class _Chunk:
    def __init__(self, content: str) -> None:
        self.content = content


class _FakeRetriever:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def retrieve(self, **kw) -> list[_Chunk]:
        self.calls.append(kw)
        return [_Chunk("分数加减：同分母相加分母不变")]


def test_persona_normalization_and_fallback():
    assert get_subject_persona("math").subject == "数学"
    assert get_subject_persona("Math").subject == "数学"
    assert get_subject_persona("语文").display == "语文"
    assert get_subject_persona("english").subject == "英语"
    # 未知学科兜底通用，render 含通用标识
    assert get_subject_persona("物理").subject == "通用"
    assert "通用" in get_subject_persona("物理").render()


def test_registry_dispatch():
    manifests = discover_subagent_manifests()
    assert get_subagent_class(manifests, "question") is QuestionSubAgent
    assert get_subagent_class(manifests, "tutor") is TutorSubAgent
    assert get_subagent_class(manifests, "diagnosis") is None  # 尚未实现


def test_build_subagent_factory():
    manifests = discover_subagent_manifests()
    provider = _FakeProvider()
    agent = build_subagent(manifests, "tutor", provider=provider)
    assert isinstance(agent, TutorSubAgent)
    # 未知业务返回 None，路由据之兜底（如 501）
    assert build_subagent(manifests, "diagnosis", provider=provider) is None


def test_question_subagent_rag_and_persona_threading():
    """出题 run()：RAG 检索 + 学科 Persona 注入 user_prompt（ADR-0030 收口 #4 后 prompt 在此组装）。"""
    provider = _FakeProvider()
    retriever = _FakeRetriever()
    agent = QuestionSubAgent(provider=provider, retriever=retriever)
    ctx = SubAgentContext(role="parent", message="帮我出2道三年级关于《分数》的数学选择题")

    asyncio.run(_drive(agent, ctx))

    # RAG 检索被调用（KnowledgeRetriever 此前为零调用死代码，现已接线）
    assert retriever.calls, "retriever.retrieve 应被调用"
    assert provider.last_gen_kwargs is not None
    user_prompt = provider.last_gen_kwargs["user_prompt"]
    # RAG 命中内容进入 user_prompt
    assert "分数加减" in user_prompt
    # 学科 Persona 注入 user_prompt
    assert "【学科人格：数学】" in user_prompt
    # spec 携题目身份（subject/grade/knowledge_point），随 prompt 进入模型上下文
    assert "数学" in user_prompt and "分数" in user_prompt


def test_expand_specs_expands_count():
    specs = [
        {"subject": "数学", "grade": 3, "knowledge_point": "分数", "qtype": "choice", "count": 2},
        {"subject": "语文", "grade": 3, "knowledge_point": "造句", "qtype": "fill", "difficulty": "easy"},
    ]
    items = expand_specs(specs)
    # count=2 展开两题；缺省 count 按 1；顺序即 q_index
    assert [it["subject"] for it in items] == ["数学", "数学", "语文"]
    assert items[2]["difficulty"] == "easy"


def test_question_subagent_run_per_item_rag_and_persona():
    """流式路径：每题独立触发 RAG + 学科 Persona 注入（不触真实 genkit）。"""
    retriever = _FakeRetriever()
    agent = QuestionSubAgent(provider=_FakeProvider(), retriever=retriever)
    ctx = SubAgentContext(role="parent", message="帮我出2道三年级数学分数选择题")

    asyncio.run(_drive(agent, ctx))

    # 两题每题触发一次检索
    assert len(retriever.calls) == 2
    # 末尾题（数学）的 user_prompt 含数学 Persona
    assert provider_user_prompt_contains(agent, "【学科人格：数学】")


def _last_user_prompt(agent) -> str | None:
    return getattr(agent.provider, "last_gen_kwargs", {}).get("user_prompt")


def provider_user_prompt_contains(agent, needle: str) -> bool:
    up = _last_user_prompt(agent)
    return up is not None and needle in up


async def _drive(agent, ctx):
    return [ev async for ev in agent.run(ctx.message, ctx)]


def test_tutor_subagent_persona_injection():
    """伴学 run()：学科 Persona 注入讲解 context（复用 TutorService 真实路径）。"""
    provider = _FakeProvider()
    agent = TutorSubAgent(provider=provider, retriever=None)
    ctx = SubAgentContext(role="child", message="英语的过去式是什么？")

    # 经 run()（悬浮助手真实入口）驱动，不经已删除的同步 explain 入口
    asyncio.run(_drive(agent, ctx))

    # 伴学把学科 persona 注入讲解 context
    assert provider.last_tutor_context is not None
    assert "【学科人格：英语】" in provider.last_tutor_context
