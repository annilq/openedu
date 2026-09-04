"""出题 SubAgent（ADR-0021）：接 RAG（KnowledgeRetriever）+ 学科 Persona 注入。

把此前零调用的 ``KnowledgeRetriever`` 接进出题流，解决「纯自由生成、未对齐教材」痛点。
复用 ``LLMProvider.generate_question``（已追加可选 ``rag_context`` / ``persona_hint`` 参数），
对既有出题路径零破坏——不传这两个参数时行为与原来完全一致。
"""
from __future__ import annotations

from app.ai.subagents.base import BaseSubAgent, SubAgentContext
from app.ai.subagents.subject_personas import get_subject_persona


class QuestionSubAgent(BaseSubAgent):
    business = "question"

    async def handle(self, intent: dict, ctx: SubAgentContext):
        subject = ctx.subject or intent.get("subject", "")
        grade = ctx.grade or intent.get("grade", 0)
        kp = ctx.knowledge_point or intent.get("knowledge_point", "")
        qtype = intent.get("qtype", "choice")
        difficulty = intent.get("difficulty", "medium")

        # 1) RAG：检索知识库对齐教材口径（出题此前未接 RAG，KnowledgeRetriever 为死代码）。
        rag_context: str | None = None
        if self.retriever is not None and (kp or ctx.question):
            chunks = self.retriever.retrieve(
                subject=subject,
                grade=grade,
                knowledge_point=kp,
                query=ctx.question or kp,
            )
            if chunks:
                rag_context = "\n".join(f"- {c.content}" for c in chunks)

        # 2) 学科 Persona 注入（按 subject 归一化取，未命中走通用兜底）。
        persona = get_subject_persona(subject)
        persona_hint = persona.render()

        # 3) 复用既有出题能力；rag_context / persona_hint 作为可选增强。
        return await self.provider.generate_question(
            subject=subject,
            grade=grade,
            knowledge_point=kp,
            qtype=qtype,
            difficulty=difficulty,
            interests=intent.get("interests"),
            focus_interest=intent.get("focus_interest"),
            rag_context=rag_context,
            persona_hint=persona_hint,
        )
