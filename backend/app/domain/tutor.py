"""AI 伴学答疑编排服务（F-302 适龄讲解 + F-304 内容安全 + T11 知识库检索）。

组装顺序：输入安全校验 → 知识库检索注入 → 调用 provider 讲解 → 输出安全校验。

``aexplain`` 是**唯一实现**（异步，供 Agent Runtime 的 async 端点调用）；``explain`` 是
为 FastAPI 同步路由保留的薄封装（内部 ``asyncio.run``，在线程池中调用无事件循环冲突）。

两者曾为复制粘贴的双份实现，导致修复只在同步侧落地、异步侧漏掉（无引擎时把
``answer=None / blocked=False`` 下发）。现在同步侧只做事件循环桥接，管道不可能再分叉。

ADR-0030：``skills`` 为 manifest 声明的 SOP（``skills/*.md``，系统受控资产），**不参与
输入安全校验**。SOP 文本里本就写着「越狱 / 成人 / 暴力 / 政治敏感一律拒绝」这类词，
若把它并进 ``check_input`` 的扫描范围，每条学生提问都会被自己的安全 SOP 判为不安全
（实测 ``check_input(tutor_sop.md)`` → 命中「越狱」）。闸门只拦**用户可控输入**
（question / knowledge_point / context），SOP 在闸门之后拼接进 prompt。
"""

import re
from collections.abc import AsyncIterator
from dataclasses import dataclass, field

from app.core.async_bridge import run_async
from app.domain.provider import EducationLLMProvider
from app.domain.retriever import KnowledgeRetriever
from app.domain.safety import SAFE_REFUSAL, check_input, check_output

# 知识库原始片段常是 OCR 教材的任意字符窗口，夹带页码 / 练习题号 / 页眉等噪声，
# 直接喂给小模型会让它读不懂、退回固有知识自编。注入模型前做保守清洗：
# 丢弃纯数字行（页码、题号）、教材版式噪声（练习X / 成长小档案 / 单元标题），
# 并把换行压成空格，便于模型按语义吸收。
_CHUNK_NOISE_RE = re.compile(
    r"^(练习[一二三四五六七八九十百零\d]+|成长小档案|图形的运动（二）\d*|我的收获.*|做一做|看一看，数一数。你发现了什么？)$"
)


def _clean_knowledge_text(text: str) -> str:
    """清洗单段知识库片段：去版式噪声、合并空白。不改语义，仅去 OCR 噪声。"""
    lines = []
    for ln in (text or "").split("\n"):
        s = ln.strip()
        if not s or s.isdigit():
            continue
        if _CHUNK_NOISE_RE.match(s):
            continue
        lines.append(s)
    return " ".join(lines)

# 引擎不可用时的兜底说明（mock 兜底已移除，provider.tutor 返回 None）。
_LLM_UNAVAILABLE = "暂无可用的 AI 引擎，无法答疑（请在「模型管理」中添加模型并设为默认）。"


@dataclass
class TutorResult:
    answer: str
    input_safe: bool
    output_safe: bool
    blocked: bool  # True 表示因安全原因返回兜底（未调用/未采用模型输出）
    reason: str | None = None
    # 答疑引用落点（前端「参考来源」条）：命中并实际注入 prompt 的资料片段溯源。
    # 为空表示本次未命中资料库（mock 检索或无相关资料）。
    sources: list["RAGSource"] = field(default_factory=list)


@dataclass
class RAGSource:
    """答疑引用落点：一段命中片段来自哪份资料，供前端展示「参考来源」链接。"""

    material_id: str
    material_name: str
    chunk_id: str
    snippet: str  # 实际注入 prompt 的清洗后片段（截断展示）

    def to_dict(self) -> dict:
        return {
            "material_id": self.material_id,
            "material_name": self.material_name,
            "chunk_id": self.chunk_id,
            "snippet": self.snippet,
        }


@dataclass
class TutorStreamChunk:
    """``aexplain_stream`` 产出的逐帧片段：溯源 / 文本增量 / 收尾。

    - ``sources``：检索命中溯源，命中即下发（早于正文，引用条可边生成边显示）。
    - ``delta``：正文文本增量（逐 token）。
    - ``done``：收尾帧，携带完整答案与拦截标记。
    """

    sources: list[RAGSource] | None = None
    delta: str | None = None
    done: bool = False
    answer: str | None = None
    blocked: bool = False
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
    ) -> tuple[str | None, list[RAGSource]]:
        """知识库检索（T11，故事 24/25）：命中则把知识点内容拼成上下文片段，
        并同时返回溯源列表（供前端「参考来源」条）。

        注：当前内置自编库为可信内容；接入外部检索源（vector/web）后，外部内容
        视为不可信输入，须先经 check_input 再注入。
        """
        if self.retriever is None:
            return None, []
        chunks = self.retriever.retrieve(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            query=query,
        )
        if not chunks:
            return None, []
        kb_lines: list[str] = []
        sources: list[RAGSource] = []
        for c in chunks:
            cleaned = _clean_knowledge_text(c.content)
            if not cleaned:
                continue
            kb_lines.append(f"- {cleaned}")
            # 仅 vector 检索的片段带 material_id/chunk_id/source_name：据此生成溯源。
            if c.material_id and c.chunk_id and c.source_name:
                sources.append(
                    RAGSource(
                        material_id=str(c.material_id),
                        material_name=c.source_name,
                        chunk_id=str(c.chunk_id),
                        snippet=cleaned[:160],
                    )
                )
        return ("\n".join(kb_lines) if kb_lines else None), sources

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
        # 对所有学生可输入字段统一校验，避免越狱指令从知识点/上下文绕过年龄锁
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
        kb_context, sources = self._retrieve(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            query=question,
        )
        effective_context = self._with_knowledge(context, kb_context)

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
        # 缺失该分支时无引擎会把 answer=None、blocked=False 的结果下发——学生侧看到
        # 空讲解，教师侧却记为一次正常答疑。
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
            sources=sources,
        )

    async def aexplain_stream(
        self,
        *,
        grade: int,
        subject: str,
        knowledge_point: str,
        context: str | None,
        question: str,
        history: list[dict] | None = None,
        skills: str = "",
    ) -> AsyncIterator[TutorStreamChunk]:
        """异步讲解（流式）：逐帧 yield 溯源 / 文本增量 / 收尾，供 SSE 边生成边下推。

        与 ``aexplain`` 走同一套安全闸门 + 知识库检索 + 输出校验，只是把模型输出从
        「一次性返回全文」改为「逐 token 下推」。溯源在检索完成后**立即**下发，
        早于正文——引用条可随首 token 一同出现，而不是等整段生成完才冒出来。
        """
        # 1) 输入安全校验
        combined = "\n".join(p for p in (question, knowledge_point, context) if p)
        inp = check_input(combined)
        if not inp.safe:
            yield TutorStreamChunk(
                done=True, answer=SAFE_REFUSAL, blocked=True, reason=inp.reason
            )
            return

        # 2) 知识库检索注入
        kb_context, sources = self._retrieve(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            query=question,
        )
        effective_context = self._with_knowledge(context, kb_context)

        # 2.5) SOP 注入（ADR-0030）：系统受控资产，放在输入闸门之后
        sop = (skills or "").strip()
        if sop:
            effective_context = (
                f"{effective_context}\n\n{sop}" if effective_context else sop
            )

        # 检索命中即下发溯源：引用条可早于正文出现
        if sources:
            yield TutorStreamChunk(sources=sources)

        # 3) 流式调用模型，逐增量下推
        parts: list[str] = []
        async for delta in self.provider.tutor_stream(
            grade=grade,
            subject=subject,
            knowledge_point=knowledge_point,
            context=effective_context,
            question=question,
            history=history,
        ):
            if delta:
                parts.append(delta)
                yield TutorStreamChunk(delta=delta)

        raw = "".join(parts)

        # 3.5) 引擎不可用：provider 未产出任何 token
        if not raw:
            yield TutorStreamChunk(
                done=True,
                answer=_LLM_UNAVAILABLE,
                blocked=True,
                reason="llm_unavailable",
            )
            return

        # 4) 输出安全校验
        out = check_output(raw)
        if not out.safe:
            yield TutorStreamChunk(
                done=True, answer=SAFE_REFUSAL, blocked=True, reason=out.reason
            )
            return

        yield TutorStreamChunk(
            done=True, answer=raw, blocked=False, reason=None, sources=sources
        )


__all__ = ["TutorService", "TutorResult"]
