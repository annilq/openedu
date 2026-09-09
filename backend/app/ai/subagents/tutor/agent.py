"""伴学 SubAgent（ADR-0024 / 文件夹化）：复用 TutorService + 学科 Persona 注入。

位于 ``app/ai/subagents/tutor/``，与本文件夹 ``manifest.py`` 一同被 AgentRuntime 发现。
``run(message, ctx)`` 异步产出 AG-UI 事件（TOOL_CALL / ASSISTANT_MESSAGE）；
安全层（输入/输出校验 + 知识库检索）由 TutorService.aexplain 保障（ADR-008 不降级）。
"""
from __future__ import annotations

from app.ai.runtime.protocol import (
    assistant_message,
    tool_call,
    tool_result,
)
from app.ai.subagents.base import BaseSubAgent, SubAgentContext
from app.ai.subagents.subject_personas import get_subject_persona
from app.domain.quota import SUBJECTS
from app.domain.tutor import TutorResult, TutorService


def detect_subject(text: str) -> str:
    """尽力从自由文本识别学科（空串表示未指定）。"""
    for s in SUBJECTS:
        if s in (text or ""):
            return s
    return ""


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
        """同步讲解入口（保留，供需要同步调用的场景）。"""
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

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        """悬浮助手入口：自由文本 → 适龄讲解（ASSISTANT_MESSAGE）。"""
        subject = detect_subject(message) or (ctx.subject or "")
        grade = ctx.grade or 0
        yield tool_call("tutor_explain", label="伴学答疑")
        result = await self.service.aexplain(
            grade=grade,
            subject=subject,
            knowledge_point="",
            context=self._effective_context(subject, ctx.context),
            question=message,
        )
        yield tool_result("tutor_explain", {"blocked": result.blocked})
        yield assistant_message(result.answer, blocked=result.blocked)
