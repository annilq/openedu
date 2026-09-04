"""ADR-0021 多 Agent 骨架运行时验证（不加载 genkit 重型依赖，可沙箱单测）。

验证 seam 的四个关键点：
1. 学科 Persona 归一化 + 未知兜底（通用）；
2. SubAgent 注册表按业务键派发，未知业务返回 None；
3. 出题 SubAgent：RAG 检索接线 + 学科 Persona 注入，并正确透传 generate_question 必填参数；
4. 伴学 SubAgent：学科 Persona 注入讲解 context（复用 TutorService.explain 真实路径）。

说明：TutorService.explain 内部用 asyncio.run 驱动 provider，故伴学测试不把 handle 包在
asyncio.run 里（避免嵌套事件循环）；改为直接调用真实 explain 并校验 persona 注入结果。
出题 SubAgent.handle 直接 await provider.generate_question（无嵌套循环），可整条跑通。
真实 LLM 调用路径（genkit）需真机 / CI runner 验证。
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass

from app.ai.subagents import build_subagent, get_subagent_class, get_subject_persona
from app.ai.subagents.base import SubAgentContext
from app.ai.subagents.question_agent import QuestionSubAgent, expand_specs
from app.ai.subagents.tutor_agent import TutorSubAgent


@dataclass
class _FakeQuestion:
    stem: str = "stem"


class _FakeProvider:
    def __init__(self) -> None:
        self.last_gen_kwargs: dict | None = None
        self.last_tutor_context: str | None = None

    async def generate_question(self, **kwargs):
        self.last_gen_kwargs = kwargs
        return _FakeQuestion()

    async def tutor(self, **kwargs):
        self.last_tutor_context = kwargs.get("context")
        return "讲解内容"


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
    assert get_subagent_class("question") is QuestionSubAgent
    assert get_subagent_class("tutor") is TutorSubAgent
    assert get_subagent_class("diagnosis") is None  # 尚未实现


def test_build_subagent_factory():
    provider = _FakeProvider()
    agent = build_subagent("tutor", provider=provider, retriever=None)
    assert isinstance(agent, TutorSubAgent)
    # 未知业务返回 None，路由据之兜底（如 501）
    assert build_subagent("diagnosis", provider=provider) is None


def test_question_subagent_rag_and_persona_threading():
    provider = _FakeProvider()
    retriever = _FakeRetriever()
    agent = QuestionSubAgent(provider=provider, retriever=retriever)
    ctx = SubAgentContext(subject="数学", grade=3, knowledge_point="分数的加减", question="")
    intent = {"qtype": "choice", "difficulty": "easy"}

    result = asyncio.run(agent.handle(intent, ctx))

    # RAG 检索被调用（KnowledgeRetriever 此前为零调用死代码，现已接线）
    assert retriever.calls, "retriever.retrieve 应被调用"
    assert provider.last_gen_kwargs is not None
    # RAG 命中内容进入 rag_context
    assert "分数加减" in (provider.last_gen_kwargs.get("rag_context") or "")
    # 学科 Persona 注入生成 prompt
    assert "【学科人格：数学】" in (provider.last_gen_kwargs.get("persona_hint") or "")
    # rag_context / persona_hint 为可选增强，不破坏既有必填参数
    assert provider.last_gen_kwargs["subject"] == "数学"
    assert provider.last_gen_kwargs["knowledge_point"] == "分数的加减"
    assert isinstance(result, _FakeQuestion)


def test_expand_specs_expands_count():
    specs = [
        {"subject": "数学", "grade": 3, "knowledge_point": "分数", "qtype": "choice", "count": 2},
        {"subject": "语文", "grade": 3, "knowledge_point": "造句", "qtype": "fill", "difficulty": "easy"},
    ]
    items = expand_specs(specs)
    # count=2 展开两题；缺省 count 按 1；顺序即 q_index
    assert [it["subject"] for it in items] == ["数学", "数学", "语文"]
    assert items[2]["difficulty"] == "easy"


def test_question_subagent_stream_augments():
    """流式路径：按 q_index 预计算 RAG + 学科 Persona（不触 genkit）。"""
    retriever = _FakeRetriever()
    agent = QuestionSubAgent(provider=_FakeProvider(), retriever=retriever)
    specs = [
        {"subject": "数学", "grade": 3, "knowledge_point": "分数的加减", "qtype": "choice", "count": 2},
        {"subject": "英语", "grade": 4, "knowledge_point": "past tense", "qtype": "fill", "count": 1},
    ]
    rag_contexts, persona_hints = agent.build_augments(
        specs, interests=None, focus_interests=["恐龙"]
    )

    # 三题（2+1）均拿到 persona，key 为 q_index
    assert sorted(persona_hints) == [0, 1, 2]
    assert "【学科人格：数学】" in persona_hints[0]
    assert "【学科人格：数学】" in persona_hints[1]
    assert "【学科人格：英语】" in persona_hints[2]
    # 检索按题触发，命中内容进入 rag_context
    assert len(retriever.calls) == 3
    assert all("分数加减" in v for v in rag_contexts.values())


def test_tutor_subagent_persona_injection():
    provider = _FakeProvider()
    agent = TutorSubAgent(provider=provider, retriever=None)
    persona = get_subject_persona("英语")

    # 同步 explain 入口（FastAPI 路由直调，不经 asyncio.run，避免嵌套事件循环）。
    result = agent.explain(
        grade=4,
        subject="英语",
        knowledge_point="past tense",
        context=persona.render(),
        question="什么是过去式？",
    )

    # 伴学把学科 persona 注入讲解 context
    assert provider.last_tutor_context is not None
    assert "【学科人格：英语】" in provider.last_tutor_context
    assert result.answer == "讲解内容"
    assert result.blocked is False
    assert result.output_safe is True
