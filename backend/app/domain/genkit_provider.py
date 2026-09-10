"""GenkitProvider（教育层）：消息级 ``LLMProvider`` + 教育专有扩展。

- 消息级 ``stream`` **委托** ``agent_core.adapters.genkit.GenkitLLMProvider``（内核适配器，
  承担 genkit 流式解码）；本类只负责把 app 侧解析到的 ``EngineResolution`` 适配为
  适配器的中性输入 ``GenkitEngine``。
- 教育专有的 ``tutor`` / ``grade_open`` 留在此扩展上（ADR-0031：通用框架不认识
  「年级 / 知识点 / 批改」）。

ADR-0030：引擎解析**单一链**——``build_provider(engine=)`` 注入；未注入时回退 ``resolve_engine()``。
"""
from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any

from agent_core.adapters.genkit import GenkitEngine, GenkitLLMProvider
from agent_core.ports import StreamEvent, TextDelta
from app.ai import resolve_engine
from app.ai.engine import EngineResolution
from app.domain.grader import GradeSchema
from app.domain.prompts import EDU_SYSTEM_PROMPT
from app.domain.provider import EducationLLMProvider
from app.domain.safety import tutor_system_prompt
from app.domain.structured import schema_field


class GenkitProvider(EducationLLMProvider):
    """单一 Genkit 栈的 LLMProvider 实现。

    ADR-0030：可接受显式引擎（家长 ``ModelConfig`` / 前端 ``model`` 解析所得）；
    为 ``None`` 时每次调用回退 ``resolve_engine()``。
    """

    def __init__(self, engine: EngineResolution | None = None) -> None:
        self._engine = engine

    def _resolve(self) -> EngineResolution | None:
        """显式引擎优先，否则回退全局解析（ADR-0030 单一解析链）。"""
        return self._engine if self._engine is not None else resolve_engine()

    def _adapter(self) -> GenkitLLMProvider | None:
        """把 app 侧 ``EngineResolution`` 适配为内核适配器的中性输入。"""
        eng = self._resolve()
        if eng is None:
            return None
        return GenkitLLMProvider(GenkitEngine(genkit=eng.genkit, model=eng.model))

    async def stream(
        self,
        system: str,
        prompt: str,
        *,
        schema: Any | None = None,
        tools: list[Any] | None = None,
        history: list[dict] | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """消息级流式产出：委托 ``agent_core`` 的 genkit 适配器。"""
        adapter = self._adapter()
        if adapter is None:
            return
        async for ev in adapter.stream(system, prompt, schema=schema, tools=tools, history=history):
            yield ev

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
            model=engine.model, system=EDU_SYSTEM_PROMPT, prompt=prompt,
            output_schema=GradeSchema,
        )
        raw = resp.output
        return {
            "correct": bool(schema_field(raw, "correct", False)),
            "score": float(schema_field(raw, "score", 0.0)),
            "explanation": schema_field(raw, "explanation", "") or (question.explanation or ""),
        }
