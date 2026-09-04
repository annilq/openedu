"""GenkitProvider（迁移 08b：统一 Genkit 全栈）。

替代原 MockProvider / LangChainProvider 的**纯单栈**实现：业务层（TutorService /
Grader / QuestionGenerator 非流式路径）只依赖 `LLMProvider` ABC，本类把调用转发到
`app/ai` 的 Genkit 编排（流式 flow 的非流式助手）。

- 真实引擎（resolve_engine 解析到）：出题 / 答疑 / 批改走 Genkit。
- 无引擎（mock / LLM_PROVIDER=mock）：确定性 mock 分支（_mock_question / _mock_tutor_text /
  关键词启发式批改），零外部依赖仍跑通闭环（原 MockProvider 逻辑已并入 flow）。
"""
from __future__ import annotations

from app.ai import generate_question as genkit_generate_question
from app.ai import grade_open as genkit_grade_open
from app.ai import mock_question as mock_question_flow
from app.ai import resolve_engine
from app.ai.flows import _mock_tutor_text, _tutor_generate
from app.domain.provider import GeneratedQuestion, LLMProvider


class GenkitProvider(LLMProvider):
    """单一 Genkit 栈的 LLMProvider 实现（迁移 08b 退役 LangChain/Mock 双栈）。"""

    async def generate_question(
        self,
        *,
        subject,
        grade,
        knowledge_point,
        qtype,
        difficulty,
        interests: list[str] | None = None,
        focus_interest: str | None = None,
        rag_context: str | None = None,
        persona_hint: str | None = None,
    ) -> GeneratedQuestion:
        engine = resolve_engine()
        if engine is not None:
            g = await genkit_generate_question(
                engine,
                subject=subject,
                grade=grade,
                knowledge_point=knowledge_point,
                qtype=qtype,
                difficulty=difficulty,
                interests=interests,
                focus_interest=focus_interest,
                rag_context=rag_context,
                persona_hint=persona_hint,
            )
            if g is not None:
                return g
        # 无真实引擎 / 真实产出不安全 → 确定性 mock 分支（保证题量完整且不落库违规内容）。
        q = mock_question_flow(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            qtype=qtype,
            difficulty=difficulty,
            interests=interests,
            focus_interest=focus_interest,
        )
        return GeneratedQuestion(
            subject=q.subject,
            grade=q.grade,
            knowledge_point=q.knowledge_point,
            qtype=q.qtype,
            stem=q.stem,
            options=q.options,
            answer=q.answer,
            explanation=q.explanation,
            difficulty=q.difficulty,
        )

    async def grade_open(self, *, question, student_answer) -> dict:
        return await genkit_grade_open(question, student_answer)

    async def tutor(
        self, *, grade, subject, knowledge_point, context, question
    ) -> str:
        engine = resolve_engine()
        if engine is None:
            return _mock_tutor_text(
                grade=grade,
                subject=subject,
                knowledge_point=knowledge_point,
                context=context,
                question=question,
            )
        # TutorService 已在 context 注入知识库检索结果，这里只做模型生成、不重复检索。
        return await _tutor_generate(
            engine,
            grade=grade,
            subject=subject,
            knowledge_point=knowledge_point,
            context=context or "",
            question=question,
        )
