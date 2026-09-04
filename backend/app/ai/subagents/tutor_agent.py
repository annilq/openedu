"""伴学 SubAgent（ADR-0021）：复用 TutorService（已半接 RAG），叠加学科 Persona 注入。

persona 通过 ``context`` 注入（TutorService.explain 的 context 为自由文本，会进入讲解 prompt），
无需改动 TutorService / provider 签名即可让讲解按学科切换语气 / 深度 / 学科约定。
安全层（domain/safety）与知识库检索仍由 TutorService 内部保障（ADR-008 不降级）。

同步入口 ``explain(...)`` 供 FastAPI 同步路由直接调用（TutorService.explain 内部自管事件循环，
外层不能再套 asyncio.run）；异步 ``handle(...)`` 为轻主管 / 未来 supervisor 的统一契约。
"""
from __future__ import annotations

from app.ai.subagents.base import BaseSubAgent, SubAgentContext
from app.ai.subagents.subject_personas import get_subject_persona
from app.domain.tutor import TutorResult, TutorService


class TutorSubAgent(BaseSubAgent):
    business = "tutor"

    def __init__(self, *, provider, retriever=None, engine=None) -> None:
        super().__init__(provider=provider, retriever=retriever, engine=engine)
        self.service = TutorService(provider=provider, retriever=retriever)

    def _effective_context(self, subject: str, base_context: str | None) -> str:
        persona = get_subject_persona(subject)
        if base_context:
            return f"{base_context}\n\n{persona.render()}".strip()
        return persona.render()

    def explain(
        self,
        *,
        grade: int,
        subject: str,
        knowledge_point: str,
        context: str | None,
        question: str,
    ) -> TutorResult:
        """同步讲解入口（route 直调）。学科 Persona 注入讲解上下文。"""
        effective_context = self._effective_context(subject, context)
        return self.service.explain(
            grade=grade,
            subject=subject,
            knowledge_point=knowledge_point,
            context=effective_context,
            question=question,
        )

    async def handle(self, intent: dict, ctx: SubAgentContext) -> TutorResult:
        subject = ctx.subject or intent.get("subject", "")
        grade = ctx.grade or intent.get("grade", 0)
        kp = ctx.knowledge_point or intent.get("knowledge_point", "")
        question = ctx.question or intent.get("question", "")

        return self.explain(
            grade=grade,
            subject=subject,
            knowledge_point=kp,
            context=ctx.context,
            question=question,
        )
