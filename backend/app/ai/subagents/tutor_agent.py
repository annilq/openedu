"""伴学 SubAgent（ADR-0021）：复用 TutorService（已半接 RAG），叠加学科 Persona 注入。

persona 通过 ``context`` 注入（TutorService.explain 的 context 为自由文本，会进入讲解 prompt），
无需改动 TutorService / provider 签名即可让讲解按学科切换语气 / 深度 / 学科约定。
安全层（domain/safety）与知识库检索仍由 TutorService 内部保障（ADR-008 不降级）。
"""
from __future__ import annotations

from app.ai.subagents.base import BaseSubAgent, SubAgentContext
from app.ai.subagents.subject_personas import get_subject_persona
from app.domain.tutor import TutorResult, TutorService


class TutorSubAgent(BaseSubAgent):
    business = "tutor"

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        self.service = TutorService(provider=provider, retriever=retriever)

    async def handle(self, intent: dict, ctx: SubAgentContext) -> TutorResult:
        subject = ctx.subject or intent.get("subject", "")
        grade = ctx.grade or intent.get("grade", 0)
        kp = ctx.knowledge_point or intent.get("knowledge_point", "")
        question = ctx.question or intent.get("question", "")

        # 学科 Persona 注入：增强 context，进入讲解 prompt（不改动既有签名）。
        persona = get_subject_persona(subject)
        effective_context = (
            f"{ctx.context}\n\n{persona.render()}".strip()
            if ctx.context
            else persona.render()
        )

        return self.service.explain(
            grade=grade,
            subject=subject,
            knowledge_point=kp,
            context=effective_context,
            question=question,
        )
