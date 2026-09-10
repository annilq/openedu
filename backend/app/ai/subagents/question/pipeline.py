"""出题管线（prompt 组装 → provider 流式 → 语义事件）。

本模块是**出题业务的完整管线**，归属 question 子包（ADR-0032 Q3：原 ``app/ai/generation.py``
的教育出题内容归位到 ``app/ai/subagents/question/``，``app/ai`` 只留 genkit/DB 桥接）：

- ``build_question_prompts``：组装 ``(system_prompt, user_prompt, spec)``——流式与落库**同一份**
  prompt，杜绝两路口径漂移。
- ``step_label``：单题进度 STEP 帧文案。
- ``stream_question``：provider 流式出题 → 教育语义事件（供 SubAgent 经 translate 转 AG-UI 帧）。
- ``generate_question``：provider 非流式出题（落库路径；内部 drain ``stream_question``）。

统一走 ``LLMProvider``（ADR-0032：废弃直连 genkit 引擎的旧路径），prompt 组装由调用方负责
（ADR-0030 收口 #4），provider 接口只收「已组装 prompt + spec」。
"""
from __future__ import annotations

from collections.abc import AsyncIterator

from agent_core.ports import LLMProvider, StructuredDone, TextDelta
from app.ai.subagents.question.parsers import (
    QuestionSchema,
    QuestionSpec,
    assemble_question,
    qtype_label,
)
from app.domain.prompts import (  # noqa: F401  (再导出)
    EDU_SYSTEM_PROMPT,
    QUESTION_SYSTEM_PROMPT,
)
from app.domain.provider import (
    GeneratedQuestion,
    QuestionCard,
    QuestionFailed,
    QuestionStreamEvent,
    ReasoningDelta,
)
from app.domain.structured import coerce_dict


def step_label(subject: str, grade: int, knowledge_point: str, qtype: str) -> str:
    """单题进度标签（STEP 帧）：``正在为《数学》3年级「分数」出选择题…``。"""
    return f"正在为《{subject}》{grade}年级「{knowledge_point}」出{qtype_label(qtype)}…"


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
) -> tuple[str, str, QuestionSpec]:
    """组装出题 prompt（ADR-0030 收口 #4：prompt 组装从 provider 搬到调用方）。

    返回 ``(system_prompt, user_prompt, spec)``：
    - ``system_prompt``：固定的出题系统约束（适龄 / JSON 输出）。
    - ``user_prompt``：情境 / 难度 / 兴趣 / RAG / Persona / 多轮历史拼装后的完整用户指令。
    - ``spec``：题目不可变身份（subject/grade/knowledge_point/qtype/difficulty），
      由调用方给出、回填空模型产出（模型不一定回写这些字段）。

    出题 SubAgent（``agent.py``）与落库路径都经由此函数组装，再交给 provider；
    provider 接口从此只收「已组装 prompt + spec」，不再泄漏 9 个业务 kwarg。
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
    return QUESTION_SYSTEM_PROMPT, user_prompt, spec


async def stream_question(
    provider: LLMProvider,
    *,
    system_prompt: str,
    user_prompt: str,
    spec: QuestionSpec,
    history: list[dict] | None = None,
) -> AsyncIterator[QuestionStreamEvent]:
    """流式出题：复用 ``provider.stream(schema=QuestionSchema)``。

    provider 产出 ``TextDelta``（推理）+ 末帧 ``StructuredDone(data=解析字典)``；本函数
    转译为教育语义事件（``ReasoningDelta`` / ``QuestionCard`` / ``QuestionFailed``），
    由出题 SubAgent 经 translate 层转成 AG-UI 帧。prompt 与安全闸门与落库路径共用。
    """
    reasoning: list[str] = []
    async for ev in provider.stream(
        system_prompt, user_prompt, schema=QuestionSchema, history=history
    ):
        if isinstance(ev, TextDelta):
            reasoning.append(ev.delta)
            yield ReasoningDelta(delta=ev.delta)
        elif isinstance(ev, StructuredDone):
            out = assemble_question(
                raw=coerce_dict(ev.data), spec=spec, reasoning="".join(reasoning).strip()
            )
            if out is None:
                yield QuestionFailed(reason="生成内容未通过安全校验")
            else:
                yield QuestionCard(
                    question=GeneratedQuestion(
                        subject=out.subject,
                        grade=out.grade,
                        knowledge_point=out.knowledge_point,
                        qtype=out.qtype,
                        stem=out.stem,
                        options=out.options,
                        answer=out.answer,
                        explanation=out.explanation,
                        difficulty=out.difficulty,
                    ),
                    reasoning=out.reasoning,
                )
            return
    yield QuestionFailed(reason="模型未返回结构化题卡")


async def generate_question(
    provider: LLMProvider,
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
    """非流式出题（落库路径）：内部 drain ``stream_question`` 取题卡。

    返回 ``GeneratedQuestion``；模型未产出 / 产出不安全（安全闸门未过）返回 ``None``，
    由调用方抛 ``LLM_UNAVAILABLE``。全程只依赖 ``LLMProvider``（ADR-0032：不再直连 genkit 引擎）。
    """
    system_prompt, user_prompt, spec = build_question_prompts(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        difficulty=difficulty, interests=interests, focus_interest=focus_interest,
        rag_context=rag_context, persona_hint=persona_hint, history=history,
    )
    async for ev in stream_question(
        provider, system_prompt=system_prompt, user_prompt=user_prompt, spec=spec, history=history
    ):
        if isinstance(ev, QuestionCard):
            return ev.question
    return None
