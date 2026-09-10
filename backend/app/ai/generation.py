"""出题生成的共享脚手架（ADR-0023 收敛 / ADR-0028 真流式）。

本模块只放**跨入口共用**的出题构造件，不登记任何 Genkit flow 端点：

- ``generate_question``：一次性结构化出题原语（落库重生成路径）。
- ``generate_question_stream``：流式出题原语，产出 ``ReasoningDelta`` / ``QuestionCard`` /
  ``QuestionFailed`` 语义事件，由 SubAgent 翻译成 AG-UI 帧。
- 出题 prompt 构造（``_build_question_clause`` / ``_build_question_prompt``）：
  **流式与落库共用同一份 prompt**，杜绝两路口径漂移。

线上契约（``QuestionSchema``）与解析器（``SchemaQuestionParser``）在
``app/ai/parsers/question.py``；genkit chunk 解码在 ``app/ai/segment.py``。
三者构成 Decode → Demux → Parse 管线，语义事件到 AG-UI 帧的转换在
``app/ai/runtime/translate.py``。

答疑（``_tutor_generate``）与批改（``grade_open``）仅被 ``GenkitProvider`` 单一消费，
已收敛进 ``app/domain/genkit_provider.py``，不在此处（避免共享内核里藏单消费者实现）。

旧的 Genkit flow 端点（``/ai/tutor/ask``、``/ai/tasks/generate``）已废弃，全部收敛到
``POST /api/v1/assistant/chat``（ADR-0024）；Genkit 仅作为底层 LLM 引擎经 ``engine.genkit``
调用，不再经 ``genkit_fastapi`` 暴露原生 action。
"""
from __future__ import annotations

from collections.abc import AsyncIterator

from pydantic import BaseModel

from app.ai.engine import EngineResolution
from app.ai.parsers.question import (
    QuestionSchema,
    QuestionSpec,
    SchemaQuestionParser,
    assemble_question,
    qtype_label,
    schema_field,
)
from app.ai.segment import decode_stream
from app.domain.provider import GeneratedQuestion, QuestionStreamEvent

# 本模块不登记 Genkit flow（端点已废弃并收敛到 /assistant/chat）；
# Genkit 仅作为底层 LLM 引擎，经 engine.genkit 调用（由 genkit_provider 触发）。


def step_label(subject: str, grade: int, knowledge_point: str, qtype: str) -> str:
    """单题进度标签（STEP 帧）：``正在为《数学》3年级「分数」出选择题…``。"""
    return f"正在为《{subject}》{grade}年级「{knowledge_point}」出{qtype_label(qtype)}…"


# ───────────────────────── 出题系统提示（流式预览 / 落库共用） ─────────────────────────
_QUESTION_SYSTEM_PROMPT = (
    "你是面向小学到初中学生的出题与批改助手。"
    "只输出适合对应年级、纯学习相关的内容，禁止任何不当、危险或超出教材的内容。"
    "始终以 JSON 返回，不要附带多余说明。"
)


def _build_question_clause(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    interests: list[str] | None,
    focus_interest: str | None,
) -> str:
    """出题语境内核（情境/难度/兴趣包装）：流式与落库共用，保证口径一致
    （ADR-0021：RAG / 学科 Persona 在调用方注入）。"""
    if focus_interest:
        clause = (
            f"请围绕主题“{focus_interest}”为{grade}年级《{subject}》的“{knowledge_point}”"
            f"出一道{qtype}题，难度{difficulty}。题目情境应以“{focus_interest}”为载体讲清知识点，"
            f"必须紧扣教材，不引入与学习无关或不当内容。"
        )
    elif interests:
        clause = (
            f"请为{grade}年级《{subject}》的“{knowledge_point}”出一道{qtype}题，"
            f"难度{difficulty}。可结合娃娃兴趣（{', '.join(interests)}）作情境包装，"
            f"但必须紧扣知识点，不得偏离教材。"
        )
    else:
        clause = (
            f"请为{grade}年级《{subject}》的“{knowledge_point}”出一道{qtype}题，"
            f"难度{difficulty}。"
        )
    return clause


def _build_question_prompt(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    interests: list[str] | None,
    focus_interest: str | None,
    rag_context: str | None = None,
    persona_hint: str | None = None,
    history: list[dict] | None = None,
) -> str:
    """出题 prompt（流式与落库**同一份**，模型产出受 ``QuestionSchema`` 约束）。"""
    clause = _build_question_clause(
        subject=subject, grade=grade, knowledge_point=knowledge_point,
        qtype=qtype, difficulty=difficulty, interests=interests, focus_interest=focus_interest,
    )
    if persona_hint:
        clause += f"\n\n{persona_hint}"
    # ADR-0021：RAG 命中内容作为教材口径参考，对齐知识点。
    if rag_context:
        clause += f"\n\n参考教材口径（仅作对齐参考，不照搬）：\n{rag_context}"
    # ADR-0026：服务端多轮——把历史对话拼入 prompt，便于「再出两道类似的」。
    if history:
        lines = "\n".join(
            f"{'用户' if m.get('role') == 'user' else '助手'}: {m.get('content', '')}"
            for m in history[-6:]
        )
        clause += f"\n\n【前面已聊过的内容，供参考】\n{lines}"
    return (
        clause + "\n\n"
        "另外用 1-3 句写出你的出题思路（情境如何选取、干扰项/答案如何设计、难度如何把控，"
        "纯学习相关），填入 reasoning 字段。"
    )


def build_question_prompts(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    interests: list[str] | None = None,
    focus_interest: str | None = None,
    rag_context: str | None = None,
    persona_hint: str | None = None,
    history: list[dict] | None = None,
) -> tuple[str, str, "QuestionSpec"]:
    """组装出题 prompt（ADR-0030 收口 #4：prompt 组装从 provider 搬到调用方）。

    返回 ``(system_prompt, user_prompt, spec)``：
    - ``system_prompt``：固定的出题系统约束（适龄 / JSON 输出）。
    - ``user_prompt``：情境 / 难度 / 兴趣 / RAG / Persona / 多轮历史拼装后的完整用户指令。
    - ``spec``：题目不可变身份（subject/grade/knowledge_point/qtype/difficulty），
      由调用方给出、回填空模型产出（模型不一定回写这些字段）。

    出题 SubAgent（``app/ai/subagents/question/agent.py``）与落库路径都经由此函数组装，
    再交给 provider；provider 接口从此只收「已组装 prompt + spec」，不再泄漏 9 个业务 kwarg。
    """
    user_prompt = _build_question_prompt(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        difficulty=difficulty, interests=interests, focus_interest=focus_interest,
        rag_context=rag_context, persona_hint=persona_hint, history=history,
    )
    spec = QuestionSpec(
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        difficulty=difficulty,
    )
    return _QUESTION_SYSTEM_PROMPT, user_prompt, spec


# ───────────────────────── 底层生成（落库路径，已组装 prompt） ─────────────────────────
async def _generate_question(
    engine: EngineResolution,
    *,
    system_prompt: str,
    user_prompt: str,
    spec: "QuestionSpec",
    history: list[dict] | None = None,
) -> GeneratedQuestion | None:
    """非流式出题核心：与流式共用同一份 prompt 与安全闸门。

    返回 GeneratedQuestion；若真实模型产出不安全（check_output 未过）返回 None，
    由调用方抛 LLM_UNAVAILABLE。
    """
    resp = await engine.genkit.generate(
        model=engine.model, system=system_prompt, prompt=user_prompt,
        output_schema=QuestionSchema,
    )
    out = assemble_question(
        raw={
            "stem": schema_field(resp.output, "stem") or "",
            "options": schema_field(resp.output, "options"),
            "answer": schema_field(resp.output, "answer") or "",
            "explanation": schema_field(resp.output, "explanation") or "",
            "reasoning": schema_field(resp.output, "reasoning") or "",
        },
        spec=spec,
    )
    if out is None:
        return None
    return GeneratedQuestion(
        subject=out.subject, grade=out.grade, knowledge_point=out.knowledge_point,
        qtype=out.qtype, stem=out.stem, options=out.options, answer=out.answer,
        explanation=out.explanation, difficulty=out.difficulty,
    )


# ───────────────────────── 流式出题核心（已组装 prompt，Decode → Parse） ─────────────────────────
async def _generate_question_stream(
    engine: EngineResolution,
    *,
    system_prompt: str,
    user_prompt: str,
    spec: "QuestionSpec",
    history: list[dict] | None = None,
) -> AsyncIterator[QuestionStreamEvent]:
    """流式出题核心：解码 chunk → 解析器判定 → 产出语义事件。

    与 ``_generate_question`` 共用同一份 prompt 与同一份 ``output_schema``，
    因此两条路径的产出形状必然一致。

    产出三类语义事件，由调用方（出题 SubAgent）经 Translate 层转成 AG-UI 帧：
    原生思维链逐段 ``ReasoningDelta`` → 结束时 ``QuestionCard``；
    模型无产出 / 安全闸门未过 → ``QuestionFailed``（显式，不静默跳过）。
    """
    sresp = engine.genkit.generate_stream(
        model=engine.model, system=system_prompt, prompt=user_prompt,
        output_schema=QuestionSchema,
    )
    parser = SchemaQuestionParser(spec=spec)
    async for seg in decode_stream(sresp.stream):
        for ev in parser.feed(seg):
            yield ev
    resp = await sresp.response
    for ev in parser.finish(getattr(resp, "output", None)):
        yield ev


# ── 对外兼容包装（保持旧业务参数签名：tests / 落库路径 tasks/router 仍用） ──
async def generate_question(
    engine: EngineResolution,
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    interests: list[str] | None = None,
    focus_interest: str | None = None,
    rag_context: str | None = None,
    persona_hint: str | None = None,
    history: list[dict] | None = None,
) -> GeneratedQuestion | None:
    """非流式出题（落库路径 / 测试兼容入口）：内部经 ``build_question_prompts`` 组装后再生成。"""
    system_prompt, user_prompt, spec = build_question_prompts(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        difficulty=difficulty, interests=interests, focus_interest=focus_interest,
        rag_context=rag_context, persona_hint=persona_hint, history=history,
    )
    return await _generate_question(
        engine, system_prompt=system_prompt, user_prompt=user_prompt, spec=spec, history=history,
    )


async def generate_question_stream(
    engine: EngineResolution,
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    interests: list[str] | None = None,
    focus_interest: str | None = None,
    rag_context: str | None = None,
    persona_hint: str | None = None,
    history: list[dict] | None = None,
) -> AsyncIterator[QuestionStreamEvent]:
    """流式出题（测试兼容入口）：内部经 ``build_question_prompts`` 组装后再生成。"""
    system_prompt, user_prompt, spec = build_question_prompts(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        difficulty=difficulty, interests=interests, focus_interest=focus_interest,
        rag_context=rag_context, persona_hint=persona_hint, history=history,
    )
    async for ev in _generate_question_stream(
        engine, system_prompt=system_prompt, user_prompt=user_prompt, spec=spec, history=history,
    ):
        yield ev


class GradeSchema(BaseModel):
    correct: bool
    score: float
    explanation: str
