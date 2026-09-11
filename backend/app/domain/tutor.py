"""AI 伴学答疑编排服务（F-302 适龄讲解 + F-304 内容安全 + T11 知识库检索）。

组装顺序：输入安全校验 → 知识库检索注入 → 调用 provider 讲解 → 输出安全校验。

``aexplain`` 是**唯一实现**（异步，供 Agent Runtime 的 async 端点调用）；``explain`` 是
为 FastAPI 同步路由保留的薄封装（内部 ``asyncio.run``，在线程池中调用无事件循环冲突）。

两者曾为复制粘贴的双份实现，导致修复只在同步侧落地、异步侧漏掉（无引擎时把
``answer=None / blocked=False`` 下发）。现在同步侧只做事件循环桥接，管道不可能再分叉。

ADR-0030：``skills`` 为 manifest 声明的 SOP（``skills/*.md``，系统受控资产），**不参与
输入安全校验**。SOP 文本里本就写着「越狱 / 成人 / 暴力 / 政治敏感一律拒绝」这类词，
若把它并进 ``check_input`` 的扫描范围，每条娃娃提问都会被自己的安全 SOP 判为不安全
（实测 ``check_input(tutor_sop.md)`` → 命中「越狱」）。闸门只拦**用户可控输入**
（question / knowledge_point / context），SOP 在闸门之后拼接进 prompt。
"""

from dataclasses import dataclass

from app.core.async_bridge import run_async
from app.domain.provider import EducationLLMProvider
from app.domain.retriever import KnowledgeRetriever
from app.domain.safety import SAFE_REFUSAL, check_input, check_output

# 引擎不可用时的兜底说明（mock 兜底已移除，provider.tutor 返回 None）。
_LLM_UNAVAILABLE = "暂无可用的 AI 引擎，无法答疑（请配置 LLM_PROVIDER 与对应 API key）。"


@dataclass
class TutorResult:
    answer: str
    input_safe: bool
    output_safe: bool
    blocked: bool  # True 表示因安全原因返回兜底（未调用/未采用模型输出）
    reason: str | None = None


class TutorService:
    def __init__(
        self,
        provider: EducationLLMProvider,
        retriever: KnowledgeRetriever | None = None,
    ) -> None:
        self.provider = provider
        self.retriever = retriever

    def _with_knowledge(self, context: str | None, kb: str | None) -> str | None:
        """把知识库命中内容拼进上下文（未命中则原样返回）。"""
        if not kb:
            return context
        if context:
            return f"{context}\n\n【知识库】\n{kb}"
        return f"【知识库】\n{kb}"

    def _retrieve(
        self,
        *,
        subject: str,
        grade: int,
        knowledge_point: str,
        query: str,
    ) -> str | None:
        """知识库检索（T11，故事 24/25）：命中则把知识点内容拼成上下文片段。

        注：当前内置自编库为可信内容；接入外部检索源（vector/web）后，外部内容
        视为不可信输入，须先经 check_input 再注入。
        """
        if self.retriever is None:
            return None
        chunks = self.retriever.retrieve(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            query=query,
        )
        if not chunks:
            return None
        return "\n".join(f"- {c.content}" for c in chunks)

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
        """同步讲解入口：在独立事件循环中驱动 ``aexplain``。"""
        return run_async(
            self.aexplain(
                grade=grade,
                subject=subject,
                knowledge_point=knowledge_point,
                context=context,
                question=question,
                history=history,
                skills=skills,
            )
        )

    async def aexplain(
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
        """异步讲解（Agent Runtime 入口）。

        同步版 ``explain`` 内部用 ``asyncio.run`` 驱动 provider，在 FastAPI 异步上下文
        （StreamingResponse 生成器）里调用会抛 ``RuntimeError``，故异步管道以本方法为准。

        ``skills``：业务 SOP（系统受控），在输入闸门**之后**拼进上下文（ADR-0030）。
        """
        # 1) 输入安全校验（越狱 / 非学习类主题）
        # 对所有娃娃可输入字段统一校验，避免越狱指令从知识点/上下文绕过年龄锁
        combined = "\n".join(p for p in (question, knowledge_point, context) if p)
        inp = check_input(combined)
        if not inp.safe:
            return TutorResult(
                answer=SAFE_REFUSAL,
                input_safe=False,
                output_safe=True,
                blocked=True,
                reason=inp.reason,
            )

        # 2) 知识库检索注入：命中则让讲解优先对齐教材口径。
        effective_context = self._with_knowledge(
            context,
            self._retrieve(
                subject=subject,
                grade=grade,
                knowledge_point=knowledge_point,
                query=question,
            ),
        )

        # 2.5) SOP 注入（ADR-0030）：系统受控资产，放在输入闸门之后，不参与 check_input。
        sop = (skills or "").strip()
        if sop:
            effective_context = (
                f"{effective_context}\n\n{sop}" if effective_context else sop
            )

        # 3) 调用模型（provider 内部已注入年龄锁系统提示）
        raw = await self.provider.tutor(
            grade=grade,
            subject=subject,
            knowledge_point=knowledge_point,
            context=effective_context,
            question=question,
            history=history,
        )

        # 3.5) 引擎不可用：provider.tutor 返回 None，降级为兜底说明。
        # 缺失该分支时无引擎会把 answer=None、blocked=False 的结果下发——娃娃侧看到
        # 空讲解，家长侧却记为一次正常答疑。
        if raw is None:
            return TutorResult(
                answer=_LLM_UNAVAILABLE,
                input_safe=True,
                output_safe=True,
                blocked=True,
                reason="llm_unavailable",
            )

        # 4) 输出安全校验（敏感词）
        out = check_output(raw)
        if not out.safe:
            return TutorResult(
                answer=SAFE_REFUSAL,
                input_safe=True,
                output_safe=False,
                blocked=True,
                reason=out.reason,
            )

        return TutorResult(
            answer=raw,
            input_safe=True,
            output_safe=True,
            blocked=False,
            reason=None,
        )


__all__ = ["TutorService", "TutorResult"]
