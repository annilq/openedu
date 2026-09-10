"""GenkitProvider（迁移 08b：统一 Genkit 全栈；ADR-0031：消息级 LLMProvider）。

实现 ``agent_core.seams.LLMProvider.stream(system, prompt, *, schema, tools, history)``：
- ``schema`` 给定 → 约束解码，产出 ``TextDelta``（推理）+ 末帧 ``StructuredDone(data=解析字典)``；
- ``tools`` 给定 → 尽力走函数调用（不同 genkit 版本 API 差异以降级保护，真机验证门禁覆盖）；
- 两者皆无 → 纯文本，逐段 ``TextDelta``。

教育特有的 ``tutor`` / ``grade_open`` 留在 ``EducationLLMProvider`` 扩展上（ADR-0031：
通用框架不认识「年级 / 知识点」）。出题的具体 prompt 组装与解析在 ``app/ai`` 教育层完成，
本类只负责把消息交给 Genkit 引擎。

ADR-0030：引擎解析**单一链**——``build_provider(engine=)`` 注入；未注入时回退 ``resolve_engine()``。
"""
from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any

from agent_core.seams import (
    StreamEvent,
    StructuredDone,
    TextDelta,
)
from app.ai import resolve_engine
from app.ai.engine import EngineResolution
from app.ai.generation import _QUESTION_SYSTEM_PROMPT, GradeSchema
from app.ai.segment import SegmentKind, decode_stream
from app.domain.provider import EducationLLMProvider
from app.domain.safety import tutor_system_prompt


def _chunk_text(chunk: object) -> str:
    """抽取 Genkit 流式 chunk 的拼接文本（兼容 content/root.text 两种形态）。"""
    parts = getattr(chunk, "content", None) or []
    out: list[str] = []
    for part in parts:
        text = getattr(getattr(part, "root", part), "text", None)
        if text:
            out.append(text)
    return "".join(out)


def _as_dict(obj: Any) -> Any:
    if obj is None:
        return None
    if isinstance(obj, dict):
        return obj
    if hasattr(obj, "model_dump"):
        return obj.model_dump()
    try:
        return dict(obj)
    except (TypeError, ValueError):
        return obj


class GenkitProvider(EducationLLMProvider):
    """单一 Genkit 栈的 LLMProvider 实现（迁移 08b 退役 LangChain/Mock 双栈）。

    ADR-0030：可接受显式引擎（家长 ``ModelConfig`` / 前端 ``model`` 解析所得）；
    为 ``None`` 时每次调用回退 ``resolve_engine()``。
    """

    def __init__(self, engine: EngineResolution | None = None) -> None:
        self._engine = engine

    def _resolve(self) -> EngineResolution | None:
        """显式引擎优先，否则回退全局解析（ADR-0030 单一解析链）。"""
        return self._engine if self._engine is not None else resolve_engine()

    async def stream(
        self,
        system: str,
        prompt: str,
        *,
        schema: Any | None = None,
        tools: list[Any] | None = None,
        history: list[dict] | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """消息级流式产出（ADR-0031 通用接口）。"""
        engine = self._resolve()
        if engine is None:
            return

        if schema is not None:
            sresp = engine.genkit.generate_stream(
                model=engine.model, system=system, prompt=prompt, output_schema=schema
            )
            async for seg in decode_stream(sresp.stream):
                if seg.kind is SegmentKind.REASONING:
                    yield TextDelta(delta=seg.text)
            resp = await sresp.response
            yield StructuredDone(data=_as_dict(getattr(resp, "output", None)))
            return

        if tools is not None:
            # 尽力走函数调用；API 差异或异常时降级为纯文本，保证不崩。
            try:
                sresp = engine.genkit.generate_stream(
                    model=engine.model, system=system, prompt=prompt, tools=tools
                )
                async for chunk in sresp.stream:
                    text = _chunk_text(chunk)
                    if text:
                        yield TextDelta(delta=text)
                await sresp.response
                return
            except Exception:  # noqa: BLE001 — 降级保护
                pass

        sresp = engine.genkit.generate_stream(model=engine.model, system=system, prompt=prompt)
        async for chunk in sresp.stream:
            text = _chunk_text(chunk)
            if text:
                yield TextDelta(delta=text)
        await sresp.response

    async def tutor(
        self,
        *,
        grade: int,
        subject: str,
        knowledge_point: str,
        context: str | None,
        question: str,
        history: list[dict] | None = None,
    ) -> str | None:
        engine = self._resolve()
        if engine is None:
            return None
        ctx = f"\n相关上下文：{context}" if context else ""
        prompt = (
            f"学生问：{question}\n"
            f"所属知识点：{knowledge_point}{ctx}\n"
            "请用简洁、鼓励的语气，结合知识点给出适合该年级学生的分步讲解，必要时举例。"
            "只讲解学习相关内容，不要回答与学习无关的话题。"
        )
        if history:
            lines = "\n".join(
                f"{'学生' if m.get('role') == 'user' else '老师'}: {m.get('content', '')}"
                for m in history[-10:]
            )
            prompt += f"\n\n【对话历史】\n{lines}\n请结合以上历史，自然衔接作答。"
        parts: list[str] = []
        async for ev in self.stream(tutor_system_prompt(grade, subject), prompt, history=history):
            if isinstance(ev, TextDelta):
                parts.append(ev.delta)
        return "".join(parts)

    async def grade_open(self, *, question, student_answer) -> dict:
        engine = self._resolve()
        if engine is None:
            raise RuntimeError(
                "未配置 LLM 引擎，无法批改（请设置 LLM_PROVIDER 与对应 API key）"
            )
        prompt = (
            f"题目：{question.stem}\n学生作答：{student_answer}\n"
            '请批改并返回 JSON：{"correct": bool, "score": float, "explanation": str}'
        )
        resp = await engine.genkit.generate(
            model=engine.model, system=_QUESTION_SYSTEM_PROMPT, prompt=prompt,
            output_schema=GradeSchema,
        )
        from app.ai.parsers.question import schema_field

        raw = resp.output
        return {
            "correct": bool(schema_field(raw, "correct", False)),
            "score": float(schema_field(raw, "score", 0.0)),
            "explanation": schema_field(raw, "explanation", "") or (question.explanation or ""),
        }
