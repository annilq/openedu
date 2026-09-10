"""GenkitProvider（迁移 08b：统一 Genkit 全栈）。

替代原 MockProvider / LangChainProvider 的**纯单栈**实现：业务层（TutorService /
Grader / QuestionGenerator 非流式路径）只依赖 `LLMProvider` ABC，本类把出题 / 答疑 /
批改的真实 Genkit 调用收敛于此（出题原语在 `app.ai.generation`，本类桥接 `app/ai` 边界）。

- 真实引擎（resolve_engine 解析到）：出题 / 答疑 / 批改走 Genkit。
- 无引擎（LLM_PROVIDER 未配置）：``generate_question`` / ``tutor`` 返回 None，
  ``grade_open`` 抛 RuntimeError，``generate_question_stream`` 空迭代（0 题），
  由上层决定降级（不再提供确定性 mock 兜底）。

ADR-0030：引擎解析**单一链**——``AgentRuntime`` 解析一次后经 ``build_provider(engine=)``
显式注入本类；未注入时才回退 ``resolve_engine()``（全局 ``LLM_PROVIDER``）。
此前本类内部一律无参解析，导致家长 ``ModelConfig`` / 前端 ``model`` 在助手链路上静默失效。
"""
from __future__ import annotations

from collections.abc import AsyncIterator

from app.ai import debug_log, resolve_engine
from app.ai.engine import EngineResolution
from app.ai.generation import (
    _QUESTION_SYSTEM_PROMPT,
    GradeSchema,
    _generate_question,
    _generate_question_stream,
)
from app.ai.parsers.question import QuestionSpec, schema_field
from app.domain.provider import GeneratedQuestion, LLMProvider, QuestionStreamEvent
from app.domain.safety import tutor_system_prompt


def _chunk_text(chunk) -> str:
    """抽取 Genkit 流式 chunk 的拼接文本（兼容 content/root.text 两种形态）。"""
    parts = getattr(chunk, "content", None) or []
    out: list[str] = []
    for part in parts:
        text = getattr(getattr(part, "root", part), "text", None)
        if text:
            out.append(text)
    return "".join(out)


class GenkitProvider(LLMProvider):
    """单一 Genkit 栈的 LLMProvider 实现（迁移 08b 退役 LangChain/Mock 双栈）。

    ADR-0030：可接受显式引擎（家长 ``ModelConfig`` / 前端 ``model`` 解析所得）；
    为 ``None`` 时每次调用回退 ``resolve_engine()``，行为与改动前一致。
    """

    def __init__(self, engine: EngineResolution | None = None) -> None:
        self._engine = engine

    def _resolve(self) -> EngineResolution | None:
        """显式引擎优先，否则回退全局解析（ADR-0030 单一解析链）。"""
        return self._engine if self._engine is not None else resolve_engine()

    async def generate_question(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        spec: "QuestionSpec",
        history: list[dict] | None = None,
    ) -> GeneratedQuestion | None:
        engine = self._resolve()
        if engine is None:
            return None
        return await _generate_question(
            engine, system_prompt=system_prompt, user_prompt=user_prompt, spec=spec, history=history,
        )

    async def generate_question_stream(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        spec: "QuestionSpec",
        history: list[dict] | None = None,
    ) -> AsyncIterator[QuestionStreamEvent]:
        """出题真流式：委托 ``app.ai.generation._generate_question_stream``。

        ADR-0030 收口 #4：只收已组装 prompt + spec，prompt 组装由出题 SubAgent 负责，
        本类不再感知 subject/grade/qtype 等业务语义。无引擎时直接结束迭代（调用方按 0 题处理），
        不再提供确定性 mock 兜底。
        """
        engine = self._resolve()
        if engine is None:
            return
        async for ev in _generate_question_stream(
            engine, system_prompt=system_prompt, user_prompt=user_prompt, spec=spec, history=history,
        ):
            yield ev

    async def grade_open(self, *, question, student_answer) -> dict:
        engine = self._resolve()
        if engine is None:
            raise RuntimeError(
                "未配置 LLM 引擎，无法批改（请设置 LLM_PROVIDER 与对应 API key）"
            )
        # ADR-0022：批改运行调试会话（parent_id 缺失自动 no-op）。
        conv_id = debug_log.start_agent_run(
            kind="grade",
            parent_id=None,
            child_id=None,
            model=engine.model,
            title="批改",
        )
        debug_log.log_agent_message(
            conversation_id=conv_id,
            role="user",
            step="input",
            content=f"题目：{getattr(question, 'stem', '')}\n学生作答：{student_answer}",
        )
        prompt = (
            f"题目：{question.stem}\n学生作答：{student_answer}\n"
            '请批改并返回 JSON：{"correct": bool, "score": float, "explanation": str}'
        )
        resp = await engine.genkit.generate(
            model=engine.model, system=_QUESTION_SYSTEM_PROMPT, prompt=prompt,
            output_schema=GradeSchema,
        )
        raw = resp.output
        result = {
            "correct": bool(schema_field(raw, "correct", False)),
            "score": float(schema_field(raw, "score", 0.0)),
            "explanation": schema_field(raw, "explanation", "")
            or (question.explanation or ""),
        }
        debug_log.log_agent_message(
            conversation_id=conv_id, role="assistant", step="output",
            content=result["explanation"], payload=result,
            model=engine.model,
        )
        debug_log.finish_agent_run(conversation_id=conv_id, status="done")
        return result

    async def tutor(
        self, *, grade, subject, knowledge_point, context, question,
        history: list[dict] | None = None,
    ) -> str | None:
        engine = self._resolve()
        if engine is None:
            return None
        # TutorService 已在 context 注入知识库检索结果，这里只做模型生成、不重复检索。
        ctx = f"\n相关上下文：{context}" if context else ""
        prompt = (
            f"学生问：{question}\n"
            f"所属知识点：{knowledge_point}{ctx}\n"
            "请用简洁、鼓励的语气，结合知识点给出适合该年级学生的分步讲解，必要时举例。"
            "只讲解学习相关内容，不要回答与学习无关的话题。"
        )
        # ADR-0026：服务端多轮——把历史对话拼入 prompt，自然衔接前轮。
        if history:
            lines = "\n".join(
                f"{'学生' if m.get('role') == 'user' else '老师'}: {m.get('content', '')}"
                for m in history[-10:]
            )
            prompt += f"\n\n【对话历史】\n{lines}\n请结合以上历史，自然衔接作答。"
        sr = engine.genkit.generate_stream(
            model=engine.model, system=tutor_system_prompt(grade, subject), prompt=prompt,
        )
        parts: list[str] = []
        async for chunk in sr.stream:
            text = _chunk_text(chunk)
            if text:
                parts.append(text)
        await sr.response
        return "".join(parts)
