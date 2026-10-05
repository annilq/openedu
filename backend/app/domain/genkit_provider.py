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

from agent_core.adapters.genkit import GenkitEngine, GenkitLLMProvider, classify_failure
from agent_core.errors import ProviderRequestError
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
    为 ``None`` 时每次调用回退 ``resolve_engine()``（无上下文则 None）。
    """

    def __init__(self, engine: EngineResolution | None = None) -> None:
        self._engine = engine

    def _resolve(self) -> EngineResolution | None:
        """显式引擎优先，否则回退解析（无家长上下文时返回 None，由上层降级）。"""
        return self._engine if self._engine is not None else resolve_engine()

    def _adapter(self) -> GenkitLLMProvider | None:
        """把 app 侧 ``EngineResolution`` 适配为内核适配器的中性输入。"""
        eng = self._resolve()
        if eng is None:
            return None
        return GenkitLLMProvider(GenkitEngine(genkit=eng.genkit, model=eng.model))

    @property
    def configured(self) -> bool:
        """引擎是否可用：显式/全局解析均拿到引擎才为 True。"""
        return self._resolve() is not None

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
        prompt = (
            f"学生问：{question}\n"
            f"所属知识点：{knowledge_point}\n"
        )
        # 知识库 grounding（ADR-0055 §13）：资料库原文是回答的唯一权威依据。
        # context 已由 TutorService 前缀「【知识库】\n」并清洗，作为独立块紧邻强约束，
        # 避免小模型忽略原文或凭空编造资料里已有的内容。
        if context:
            prompt += (
                f"{context}\n"
                "以上【知识库】中的教材原文是回答的唯一权威依据。"
                "请严格依据原文作答：优先直接采用原文里的定义、判断步骤与例子；"
                "不得编造教材之外的内容，也不得用你自己的例子替换教材例子；"
                "若原文已给出判断步骤，就按原文步骤讲解。\n"
            )
        prompt += (
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
                "未配置模型，无法批改（请在「模型管理」中添加模型并设为默认）"
            )
        prompt = (
            f"题目：{question.stem}\n学生作答：{student_answer}\n"
            '请批改并返回 JSON：{"correct": bool, "score": float, "explanation": str}'
        )
        try:
            resp = await engine.genkit.generate(
                model=engine.model, system=EDU_SYSTEM_PROMPT, prompt=prompt,
                output_schema=GradeSchema,
            )
        except Exception as exc:  # noqa: BLE001 — 归类后抛出，绝不让厂商原因被上层笼统吞掉
            # 本方法直接调 genkit（不经适配器 stream），故须自行归类（ADR-0038）：
            # 未归类时 401 会以原始 GenkitError 冒到顶层，被兜底 500 抹成「服务器内部错误」。
            failure = classify_failure(exc)
            if isinstance(failure, ProviderRequestError):
                raise failure from exc
            raise
        raw = resp.output
        return {
            "correct": bool(schema_field(raw, "correct", False)),
            "score": float(schema_field(raw, "score", 0.0)),
            "explanation": schema_field(raw, "explanation", "") or (question.explanation or ""),
        }
