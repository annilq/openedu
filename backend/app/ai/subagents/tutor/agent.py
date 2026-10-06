"""伴学 SubAgent（ADR-0024 / 文件夹化）：复用 TutorService + 学科 Persona 注入。

位于 ``app/ai/subagents/tutor/``，与 manifest.py 一同被 agent_core.AgentRuntime 发现加载。
``run(message, ctx)`` 异步产出 AG-UI 事件（TOOL_CALL / ASSISTANT_MESSAGE）；
安全层（输入/输出校验 + 知识库检索）由 TutorService.aexplain 保障（ADR-008 不降级）。

业务字段（subject/grade/context）走 agent_core 的 ``SubAgentContext.extra``（core 不感知
任何教育语义），由端点统一注入（见 app/features/assistant/router.py）。
"""
from __future__ import annotations

from agent_core.protocol import assistant_message, data_event
from agent_core.subagent import BaseSubAgent, SubAgentContext
from app.ai.subagents.subject_personas import get_subject_persona
from app.domain.subjects import SUBJECTS
from app.domain.tutor import TutorService


def detect_subject(text: str) -> str:
    """尽力从自由文本识别学科（空串表示未指定）。端点路由与配额复用，避免二次调用。"""
    for s in SUBJECTS:
        if s in (text or ""):
            return s
    return ""


def _courseware_hint_context(
    courseware: dict, base_context: str | None
) -> str:
    """课件答错场景的分级提示约束；身份仍是教师，内容受众是学生。"""
    classroom = (
        "【课堂练习分级提示】\n"
        "这是教师账户为大屏前学生触发的口头答错引导，不是可复核作答。\n"
        "按教师消息中指定的级别只给一级提示："
        "第1级只提醒观察方向；第2级拆出关键条件；第3级指出下一步操作。\n"
        "任何级别都不得直接给出答案、最终结论或完整解法；"
        "不得创建任务，不得记录作答、错题或掌握度。\n"
        f"课件：{courseware.get('courseware_id') or '未指定'}；"
        f"环节：{courseware.get('section_id') or '未指定'}；"
        f"知识点：{courseware.get('knowledge_point') or '未指定'}。"
    )
    return f"{base_context}\n\n{classroom}" if base_context else classroom


class TutorSubAgent(BaseSubAgent):
    business = "tutor"

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        self.service = TutorService(provider=provider, retriever=retriever)

    def _effective_context(self, subject: str, base_context: str | None) -> str:
        """学科 Persona 拼进上下文。

        业务 SOP（ADR-0030）**不走这里**——本方法的产物会被 TutorService 纳入
        ``check_input`` 扫描范围，而 SOP 文本里本就含「越狱 / 成人 / 暴力 / 政治敏感」等
        安全词，并进去会导致每条学生提问被自己的 SOP 判为不安全。SOP 由 aexplain 在闸门后注入。
        """
        persona = get_subject_persona(subject).render()
        if base_context:
            return f"{base_context}\n\n{persona}".strip()
        return persona

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        """悬浮助手入口：自由文本 → 适龄讲解（流式 ASSISTANT_MESSAGE）。"""
        courseware = ctx.extra.get("courseware")
        is_courseware = isinstance(courseware, dict)
        courseware = courseware if is_courseware else {}
        subject = str(courseware.get("subject") or "") or detect_subject(message) or (
            ctx.extra.get("subject") or ""
        )
        grade = int(courseware.get("grade") or ctx.extra.get("grade") or 0)
        knowledge_point = str(courseware.get("knowledge_point") or "")
        base_context = ctx.extra.get("context")
        if is_courseware:
            base_context = _courseware_hint_context(courseware, base_context)
        tc = self._tool("tutor_explain", label="伴学答疑")
        yield tc.call
        # 流式讲解：溯源（rag_sources）先于正文下发，正文逐 token 下推，
        # 前端边接收边渲染——彻底消除「一直显示伴学答疑、无 SSE 进度」的观感
        # （原为 tutor() 缓冲整段、65s 后才一次性吐出，SSE 被视为卡死）。
        async for chunk in self.service.aexplain_stream(
            grade=grade,
            subject=subject,
            knowledge_point=knowledge_point,
            context=self._effective_context(subject, base_context),
            question=message,
            history=ctx.history,
            # ADR-0030：SOP 在输入安全闸门之后注入（见 TutorService.aexplain_stream）
            skills=ctx.skills,
        ):
            if chunk.sources and not chunk.done:
                # 答疑引用条：把命中并注入 prompt 的资料片段溯源作为 DATA 帧下发，
                # 前端在答案下方渲染「参考来源」。早于正文 → 引用条随首 token 出现。
                # 仅非 done 帧下发：done 帧也带 sources 仅是冗余兜底，避免重复下发造成
                # 前端引用条重复渲染。
                yield data_event(
                    [s.to_dict() for s in chunk.sources],
                    extra={"type": "rag_sources"},
                )
            elif chunk.delta:
                yield assistant_message(chunk.delta)
            elif chunk.done:
                yield tc.result({"blocked": chunk.blocked})
                # 仅拦截态才补一条收尾消息（拒绝话术）；正常流正文已由 delta 拼出。
                if chunk.blocked:
                    answer = chunk.answer or ""
                    if is_courseware and chunk.reason == "llm_unavailable":
                        answer = (
                            "未配置模型，无法生成课堂提示。请在「模型管理」中添加模型并设为默认后重试。"
                        )
                    yield self._finish(answer, blocked=True)
