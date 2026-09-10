"""伴学 SubAgent（ADR-0024 / 文件夹化）：复用 TutorService + 学科 Persona 注入。

位于 ``app/ai/subagents/tutor/``，与本文件夹 ``manifest.py`` 一同被 AgentRuntime 发现。
``run(message, ctx)`` 异步产出 AG-UI 事件（TOOL_CALL / ASSISTANT_MESSAGE）；
安全层（输入/输出校验 + 知识库检索）由 TutorService.aexplain 保障（ADR-008 不降级）。
"""
from __future__ import annotations

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

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        self.service = TutorService(provider=provider, retriever=retriever)

    def _effective_context(self, subject: str, base_context: str | None) -> str:
        """学科 Persona 拼进上下文。

        注意：业务 SOP（ADR-0030）**不走这里**——本方法的产物会被
        ``TutorService`` 纳入 ``check_input`` 扫描范围，而 SOP 文本里本就含
        「越狱 / 成人 / 暴力 / 政治敏感」等安全词，并进去会导致每条娃娃提问
        被自己的 SOP 判为不安全。SOP 由 ``aexplain(skills=)`` 在闸门之后注入。
        """
        persona = get_subject_persona(subject).render()
        if base_context:
            return f"{base_context}\n\n{persona}".strip()
        return persona

    def explain(
        self,
        *,
        grade: int,
        subject: str,
        knowledge_point: str,
        context: str | None,
        question: str,
        history: list[dict] | None = None,
        skills: str = "",
    ) -> TutorResult:
        """同步讲解入口（保留，供需要同步调用的场景）。"""
        effective_context = self._effective_context(subject, context)
        return self.service.explain(
            grade=grade,
            subject=subject,
            knowledge_point=knowledge_point,
            context=effective_context,
            question=question,
            history=history,
            skills=skills,
        )

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        """悬浮助手入口：自由文本 → 适龄讲解（ASSISTANT_MESSAGE）。"""
        subject = detect_subject(message) or (ctx.subject or "")
        grade = ctx.grade or 0
        tc = self._tool("tutor_explain", label="伴学答疑")
        yield tc.call
        result = await self.service.aexplain(
            grade=grade,
            subject=subject,
            knowledge_point="",
            context=self._effective_context(subject, ctx.context),
            question=message,
            history=ctx.history,
            # ADR-0030：SOP 在输入安全闸门之后注入（见 TutorService.aexplain）
            skills=ctx.skills,
        )
        yield tc.result({"blocked": result.blocked})
        yield self._finish(result.answer, blocked=result.blocked)
