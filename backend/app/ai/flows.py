"""出题 / 答疑 / 批改的共享生成层（ADR-0015 修订 / 迁移 08b：统一 Genkit 全栈）。

本模块只保留被各 SubAgent 复用的底层一次性生成能力（SSE 流式由 SubAgent 在事件层封装）：

- 出题：``generate_question``（一次性结构化输出，落库 / 逐题 DATA 事件共用）。
- 答疑：``_tutor_generate``（一次性讲解文本）。
- 批改：``grade_open``（开放题批改）。
- Mock 分支：``resolve_engine`` 返回 None（无 key / LLM_PROVIDER=mock）时走确定性假数据
  （``_mock_question`` / ``_mock_tutor_text``），零外部依赖仍跑通闭环。

旧的 Genkit flow 端点（``/ai/tutor/ask``、``/ai/tasks/generate``）已废弃，全部收敛到
``POST /api/v1/assistant/chat``（ADR-0024）；Genkit 仅作为底层 LLM 引擎经 ``engine.genkit`` 调用，
不再经 ``genkit_fastapi`` 暴露原生 action。
"""
from __future__ import annotations

import hashlib
import random
import uuid
from typing import Any

from pydantic import BaseModel

from app.ai import debug_log
from app.ai.engine import EngineResolution, resolve_engine
from app.domain.provider import GeneratedQuestion
from app.domain.safety import check_output, tutor_system_prompt

# 本模块不再注册 Genkit flow（端点已废弃并收敛到 /assistant/chat）；
# Genkit 仅作为底层 LLM 引擎，经 engine.genkit 调用。

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


# ───────────────────────── Mock 分支（一次性模拟数据源，确定性） ─────────────────────────
def _mock_seed(subject: str, grade: int, knowledge_point: str, qtype: str) -> random.Random:
    seed = int(hashlib.sha256(f"{subject}{grade}{knowledge_point}{qtype}".encode()).hexdigest(), 16)
    return random.Random(seed)


def _mock_question(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    interests: list[str] | None = None,
    focus_interest: str | None = None,
) -> QuestionOut:
    rng = _mock_seed(subject, grade, knowledge_point, qtype)
    if focus_interest:
        flavor = f"（兴趣：{focus_interest}）"
        focus_desc = f"围绕主题「{focus_interest}」"
    elif interests:
        flavor = f"（兴趣池：{', '.join(interests)}）"
        focus_desc = f"结合兴趣（{', '.join(interests)}）"
    else:
        flavor = ""
        focus_desc = "紧扣教材"
    options: list[str] | None = None
    if qtype == "choice":
        correct = rng.randint(0, 3)
        opts = ["A", "B", "C", "D"]
        answer = opts[correct]
        stem = f"【{subject}】{knowledge_point} 的正确答案是什么？(难度 {difficulty}){flavor}"
        explanation = f"根据{knowledge_point}的定义，正确答案是 {answer}。"
    elif qtype == "calc":
        a, b = rng.randint(1, 20), rng.randint(1, 20)
        answer = str(a + b)
        stem = f"计算：{a} + {b} = ?{flavor}"
        explanation = f"{a} + {b} = {answer}。"
    elif qtype == "fill":
        answer = f"示例{grade}年级{knowledge_point}"
        stem = f"请根据“{knowledge_point}”填空。{flavor}"
        explanation = f"应填写：{answer}。"
    else:  # open
        answer = f"关于{knowledge_point}的要点说明。"
        stem = f"请简述{knowledge_point}。{flavor}"
        explanation = answer
    reasoning = (
        f"针对{grade}年级《{subject}》「{knowledge_point}」设计一道{_qtype_label(qtype)}"
        f"（难度{difficulty}）。情境选取：{focus_desc}，确保贴合学生生活经验；"
        f"答案/干扰项按该年级常见误区设置，答案唯一且可验证；难度控制在 {difficulty}，"
        f"符合课标要求。"
    )
    return QuestionOut(
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        stem=stem,
        options=options,
        answer=answer,
        explanation=explanation,
        difficulty=difficulty,
        reasoning=reasoning,
    )


def _mock_tutor_text(
    *,
    grade: int,
    subject: str,
    knowledge_point: str,
    context: str | None,
    question: str,
) -> str:
    return (
        f"【{subject} · {grade}年级】关于“{knowledge_point}”：\n"
        f"你问的“{question}”，我们可以这样想——先回顾{knowledge_point}的定义，"
        f"再一步步分析。举例来说，{knowledge_point}常出现在{subject}的基础练习里，"
        f"多练几道就会啦！如果有具体题目，可以把题目发给我哦～"
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


async def grade_open(
    question: Any,
    student_answer: str,
    *,
    engine: EngineResolution | None = None,
    parent_id: uuid.UUID | None = None,
    child_id: uuid.UUID | None = None,
) -> dict:
    """开放题批改（非流式路径）：有真实引擎走 Genkit，否则确定性 mock 启发式。

    统一单栈后替代原 LangChainProvider.grade_open；question 为 ORM Question
    （含 .stem/.knowledge_point/.explanation）。mock 分支按知识点关键词包含判定，
    保证零 key 也能批改（沿用原 MockProvider.grade_open 语义）。

    parent_id/child_id 仅用于 ADR-0022 调试落库：由调用方（批改入口）传入；
    缺省 None 时调试会话不创建（安全 no-op），不破坏既有调用链。
    """
    if engine is None:
        engine = resolve_engine()
    # ADR-0022：批改运行调试会话（parent_id 缺失自动 no-op）。
    conv_id = debug_log.start_agent_run(
        kind="grade",
        parent_id=parent_id,
        child_id=child_id,
        model=engine.model if engine is not None else "mock",
        title="批改",
    )
    debug_log.log_agent_message(
        conversation_id=conv_id,
        role="user",
        step="input",
        content=f"题目：{getattr(question, 'stem', '')}\n学生作答：{student_answer}",
    )
    if engine is None:
        correct = bool(student_answer) and any(
            kw in (student_answer or "") for kw in (question.knowledge_point,)
        )
        result = {
            "correct": correct,
            "score": 1.0 if correct else 0.0,
            "explanation": question.explanation or "已收到作答。",
        }
        debug_log.log_agent_message(
            conversation_id=conv_id, role="assistant", step="output",
            content=result["explanation"], payload=result, model="mock",
        )
        debug_log.finish_agent_run(conversation_id=conv_id, status="done")
        return result
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
        "correct": bool(_schema_field(raw, "correct", False)),
        "score": float(_schema_field(raw, "score", 0.0)),
        "explanation": _schema_field(raw, "explanation", "")
        or (question.explanation or ""),
    }
    debug_log.log_agent_message(
        conversation_id=conv_id, role="assistant", step="output",
        content=result["explanation"], payload=result,
        model=engine.model if engine is not None else None,
    )
    debug_log.finish_agent_run(conversation_id=conv_id, status="done")
    return result


def _chunk_text(chunk: Any) -> str:
    parts = getattr(chunk, "content", None) or []
    out: list[str] = []
    for part in parts:
        text = getattr(getattr(part, "root", part), "text", None)
        if text:
            out.append(text)
    return "".join(out)


async def _tutor_generate(
    engine: EngineResolution,
    *,
    grade: int,
    subject: str,
    knowledge_point: str,
    context: str | None,
    question: str,
) -> str:
    """答疑生成（不含知识库检索）：逐 token 产出讲解文本，整体拼接返回。

    检索由调用方（flow / TutorService）在 context 中注入；本助手只负责模型生成，
    供 GenkitProvider.tutor 等非流式入口复用，避免重复检索。
    """
    ctx = f"\n相关上下文：{context}" if context else ""
    prompt = (
        f"学生问：{question}\n"
        f"所属知识点：{knowledge_point}{ctx}\n"
        "请用简洁、鼓励的语气，结合知识点给出适合该年级学生的分步讲解，必要时举例。"
        "只讲解学习相关内容，不要回答与学习无关的话题。"
    )
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

