"""出题生成的共享脚手架 + 单一安全闸门（ADR-0023 收敛 / 迁移 08b：Genkit 全栈）。

本模块只放**跨入口共用**的出题构造件，不登记任何 Genkit flow 端点：

- ``generate_question``：一次性结构化出题原语（落库重生成路径 + 出题 SubAgent 经
  ``LLMProvider`` 复用，见 ``app/domain/genkit_provider.py``）。
- 共享脚手架：题卡 schema（``QuestionOut`` / ``QuestionSchema`` / ``GradeSchema``）、
  出题 prompt 构造（``_build_question_clause`` / ``_build_question_prompt``）、
  JSON 宽容解析（``_parse_question_json`` / ``_schema_field``）、
  装配 + 安全闸门（``_assemble_question``，统一经 ``check_output`` 校验）。

答疑（``_tutor_generate``）与批改（``grade_open``）仅被 ``GenkitProvider`` 单一消费，
已收敛进 ``app/domain/genkit_provider.py``，不在此处（避免共享内核里藏单消费者实现）。

旧的 Genkit flow 端点（``/ai/tutor/ask``、``/ai/tasks/generate``）已废弃，全部收敛到
``POST /api/v1/assistant/chat``（ADR-0024）；Genkit 仅作为底层 LLM 引擎经 ``engine.genkit`` 调用，
不再经 ``genkit_fastapi`` 暴露原生 action。
"""
from __future__ import annotations

from typing import Any

from pydantic import BaseModel

from app.ai.engine import EngineResolution
from app.domain.provider import GeneratedQuestion
from app.domain.safety import check_output

# 本模块不登记 Genkit flow（端点已废弃并收敛到 /assistant/chat）；
# Genkit 仅作为底层 LLM 引擎，经 engine.genkit 调用（由 genkit_provider 触发）。


class QuestionOut(BaseModel):
    """出题流式输出 schema（与 GeneratedQuestion / Question 字段对齐，前端 QuestionPreview 映射）。

    `reasoning`：出题推理过程（ADR-0017），仅用于流式预览态展示，不落库。
    """

    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = None
    answer: str
    explanation: str
    difficulty: str
    reasoning: str = ""


def _qtype_label(qtype: str) -> str:
    return {
        "calc": "计算题",
        "fill": "填空题",
        "choice": "选择题",
        "open": "应用题",
    }.get(qtype, "题目")


def _step_label(subject: str, grade: int, knowledge_point: str, qtype: str) -> str:
    return f"正在为《{subject}》{grade}年级「{knowledge_point}」出{_qtype_label(qtype)}…"


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
    """出题语境内核（情境/难度/兴趣包装）：被「出题 prompt」与「推理 prompt」共用，
    保证两阶段口径一致（ADR-0021：RAG / 学科 Persona 在调用方注入）。"""
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
    reasoning_hint: str | None = None,
) -> str:
    # ADR-0021：学科 Persona 注入（语气/适龄/学科约定），让同业务跨学科表现一致且可控。
    clause = _build_question_clause(
        subject=subject, grade=grade, knowledge_point=knowledge_point,
        qtype=qtype, difficulty=difficulty, interests=interests, focus_interest=focus_interest,
    )
    if persona_hint:
        clause += f"\n\n{persona_hint}"
    # ADR-0021：RAG 命中内容作为教材口径参考，对齐知识点（出题此前未接 RAG）。
    if rag_context:
        clause += f"\n\n参考教材口径（仅作对齐参考，不照搬）：\n{rag_context}"
    # 把第一阶段流式产出的推理回灌，保证题卡与展示的「思路」一致（避免两阶段口径漂移）。
    if reasoning_hint:
        clause += f"\n\n（出题思路参考：{reasoning_hint}）"
    return (
        clause + '返回 JSON：'
        '{"stem": str, "options": list[str]|null, "answer": str, "explanation": str, '
        '"reasoning": str}'
        '（reasoning 为本题的出题推理过程：简述情境选取、干扰项/答案设计思路、难度控制，'
        '约 1-3 句；纯学习相关）'
    )


def _parse_question_json(text: str) -> dict | None:
    """从模型流式输出中宽容解析题卡 JSON：去 markdown 围栏、截取首个 {...}。

    返回 dict；解析失败（含空/非 JSON）返回 None，由调用方回退 mock。
    """
    import json as _json
    import re as _re

    if not text:
        return None
    s = text.strip()
    # 去 ```json ... ``` 围栏
    m = _re.search(r"```(?:json)?\s*(.*?)```", s, _re.DOTALL)
    if m:
        s = m.group(1).strip()
    start = s.find("{")
    end = s.rfind("}")
    if start == -1 or end == -1 or end < start:
        return None
    s = s[start : end + 1]
    try:
        obj = _json.loads(s)
    except Exception:
        return None
    if not isinstance(obj, dict):
        return None
    return obj


def _schema_field(obj: Any, name: str, default: Any = None) -> Any:
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


def _assemble_question(
    *,
    raw: dict,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    reasoning: str = "",
) -> QuestionOut | None:
    """共享装配 / 安全闸门：解析 dict → check_output → 类型化题卡。

    ``generate_question``（落库 / 逐题 DATA 事件共用）经此装配与安全检查，
    产出不安全时由各自调用方回退（落库路径回退 mock）。

    ``raw`` 为模型产出（键：stem/options/answer/explanation/reasoning）；
    ``check_output`` 未过返回 None，由各自调用方决定回退（落库路径回退 mock，
    流式路径 skip 该题）。
    """
    stem = raw.get("stem") or ""
    options = raw.get("options")
    answer = raw.get("answer") or ""
    explanation = raw.get("explanation") or ""
    verdict = check_output(f"{stem} {answer} {explanation}")
    if not verdict.safe:
        return None
    return QuestionOut(
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        difficulty=difficulty,
        stem=stem,
        options=options,
        answer=answer,
        explanation=explanation,
        reasoning=reasoning or (raw.get("reasoning") or ""),
    )


# ───────────────────────── 底层生成（复用既有引擎调用，被 flow 与落库路径共用） ─────────────────────────
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
) -> GeneratedQuestion | None:
    """非流式出题（落库路径）：复用流式同款 prompt + 安全闸门。

    返回 GeneratedQuestion；若真实模型产出不安全（check_output 未过）返回 None，
    由调用方回退（落库路径回退 mock，保证不落库违规内容且题量不丢）。
    """
    prompt = _build_question_prompt(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        difficulty=difficulty, interests=interests, focus_interest=focus_interest,
        rag_context=rag_context, persona_hint=persona_hint,
    )
    resp = await engine.genkit.generate(
        model=engine.model, system=_QUESTION_SYSTEM_PROMPT, prompt=prompt,
        output_schema=QuestionSchema,
    )
    raw = resp.output
    out = _assemble_question(
        raw={
            "stem": _schema_field(raw, "stem") or "",
            "options": _schema_field(raw, "options"),
            "answer": _schema_field(raw, "answer") or "",
            "explanation": _schema_field(raw, "explanation") or "",
            "reasoning": _schema_field(raw, "reasoning") or "",
        },
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        difficulty=difficulty,
    )
    if out is None:
        return None
    return GeneratedQuestion(
        subject=out.subject, grade=out.grade, knowledge_point=out.knowledge_point,
        qtype=out.qtype, stem=out.stem, options=out.options, answer=out.answer,
        explanation=out.explanation, difficulty=out.difficulty,
    )


class QuestionSchema(BaseModel):
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = None
    answer: str
    explanation: str
    difficulty: str
    reasoning: str = ""


class GradeSchema(BaseModel):
    correct: bool
    score: float
    explanation: str
