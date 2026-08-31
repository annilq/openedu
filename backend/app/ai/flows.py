"""Genkit 流式 flow（ADR-0015）：答疑逐字 + 出题逐张题卡。

- 答疑：文本 token 流式（注入 tutor_system_prompt 年龄锁 + 知识库接地）。
- 出题：逐题结构化产出（题卡逐张浮现），每题经 check_output 后产出。
安全层复用 domain/safety；genkit 经 engine 引入（仅 app/ai 边界 import）。
"""
from __future__ import annotations

from typing import Any, AsyncIterator

from pydantic import BaseModel

from app.ai.engine import EngineResolution
from app.domain.provider import GeneratedQuestion
from app.domain.retriever import build_retriever
from app.domain.safety import check_output, tutor_system_prompt

# 出题系统提示（落库路径与流式预览路径共用，保证产物一致）。
_QUESTION_SYSTEM_PROMPT = (
    "你是面向小学到初中学生的出题与批改助手。"
    "只输出适合对应年级、纯学习相关的内容，禁止任何不当、危险或超出教材的内容。"
    "始终以 JSON 返回，不要附带多余说明。"
)


def _build_question_prompt(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    interests: list[str] | None,
    focus_interest: str | None,
) -> str:
    """构造单题出题 prompt（流式预览与落库路径共用，保证产物一致）。"""
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
    return (
        clause + '返回 JSON：'
        '{"stem": str, "options": list[str]|null, "answer": str, "explanation": str}'
    )


def _schema_field(obj: Any, name: str, default: Any = None) -> Any:
    """兼容 QuestionSchema 实例（属性）与 dict 兜底（极端解析异常时）。"""
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


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
) -> GeneratedQuestion | None:
    """非流式出题（落库路径）：复用流式同款 prompt + 安全闸门。

    返回 GeneratedQuestion；若真实模型产出不安全（check_output 未过）返回 None，
    由调用方回退 MockProvider，保证不落库违规内容且题量不丢。
    """
    prompt = _build_question_prompt(
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        difficulty=difficulty,
        interests=interests,
        focus_interest=focus_interest,
    )
    resp = await engine.genkit.generate(
        model=engine.model,
        system=_QUESTION_SYSTEM_PROMPT,
        prompt=prompt,
        output_schema=QuestionSchema,
    )
    raw = resp.output
    stem = _schema_field(raw, "stem") or ""
    options = _schema_field(raw, "options")
    answer = _schema_field(raw, "answer") or ""
    explanation = _schema_field(raw, "explanation") or ""
    verdict = check_output(f"{stem} {answer} {explanation}")
    if not verdict.safe:
        return None
    return GeneratedQuestion(
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        stem=stem,
        options=options,
        answer=answer,
        explanation=explanation,
        difficulty=difficulty,
    )


class QuestionSchema(BaseModel):
    """出题流式输出 schema（与 GeneratedQuestion / Question 字段对齐）。"""

    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = None
    answer: str
    explanation: str
    difficulty: str


def _chunk_text(chunk: Any) -> str:
    """从 Genkit GenerateResponseChunk 提取文本增量（兼容 Part RootModel）。"""
    parts = getattr(chunk, "content", None) or []
    out: list[str] = []
    for part in parts:
        text = getattr(getattr(part, "root", part), "text", None)
        if text:
            out.append(text)
    return "".join(out)


async def tutor_stream(
    engine: EngineResolution,
    *,
    grade: int,
    subject: str,
    knowledge_point: str,
    context: str | None,
    question: str,
) -> AsyncIterator[str]:
    """答疑流式：逐 token 产出讲解文本。调用方负责 check_input（前）与 check_output（后）。"""
    retriever = build_retriever()
    ctx = f"\n相关上下文：{context}" if context else ""
    if retriever is not None:
        chunks = retriever.retrieve(
            subject=subject, grade=grade, knowledge_point=knowledge_point, query=question
        )
        if chunks:
            kb = "\n".join(f"- {c.content}" for c in chunks)
            ctx = f"{ctx}\n\n【知识库】\n{kb}".strip()
    prompt = (
        f"学生问：{question}\n"
        f"所属知识点：{knowledge_point}{ctx}\n"
        "请用简洁、鼓励的语气，结合知识点给出适合该年级学生的分步讲解，必要时举例。"
        "只讲解学习相关内容，不要回答与学习无关的话题。"
    )
    sr = engine.genkit.generate_stream(
        model=engine.model,
        system=tutor_system_prompt(grade, subject),
        prompt=prompt,
    )
    async for chunk in sr.stream:
        text = _chunk_text(chunk)
        if text:
            yield text
    await sr.response  # 收尾，确保流结束


async def generate_questions_stream(
    engine: EngineResolution,
    *,
    specs: list[Any],
    interests: list[str] | None = None,
    focus_interests: list[str] | None = None,
) -> AsyncIterator[QuestionSchema]:
    """出题流式：逐题产出（题卡逐张浮现）。每题经 check_output 通过后才 yield。"""
    n_focus = len(focus_interests) if focus_interests else 0
    idx = 0
    for sp in specs:
        if isinstance(sp, dict):
            subject = str(sp.get("subject", ""))
            grade = int(sp.get("grade", 0))
            knowledge_point = str(sp.get("knowledge_point", ""))
            qtype = str(sp.get("qtype", ""))
            difficulty = str(sp.get("difficulty", "medium"))
            count = int(sp.get("count", 1))
        else:
            subject = sp.subject
            grade = sp.grade
            knowledge_point = sp.knowledge_point
            qtype = sp.qtype
            difficulty = sp.difficulty
            count = sp.count
        for _ in range(max(0, count)):
            focus = focus_interests[idx % n_focus] if n_focus else None
            idx += 1
            prompt = _build_question_prompt(
                subject=subject,
                grade=grade,
                knowledge_point=knowledge_point,
                qtype=qtype,
                difficulty=difficulty,
                interests=interests,
                focus_interest=focus,
            )
            sr = engine.genkit.generate_stream(
                model=engine.model,
                system=_QUESTION_SYSTEM_PROMPT,
                prompt=prompt,
                output_schema=QuestionSchema,
            )
            async for _chunk in sr.stream:
                pass  # 消费流以推进生成；最终题由 response 给出（字段级流式由 chunk_type 预留）
            result = await sr.response
            # 流式安全：整题校验通过才下发，避免违规片段闪现（ADR-0015 决策 5）
            verdict = check_output(f"{result.stem} {result.answer} {result.explanation}")
            if not verdict.safe:
                continue
            yield result
