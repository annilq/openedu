"""出题 / 答疑 / 批改的共享生成层（ADR-0015 修订 / 迁移 08b：统一 Genkit 全栈）。

本模块只保留被各 SubAgent 复用的底层生成能力：

- 出题：``generate_question``（非流式落库路径）+ ``generate_questions_stream``（流式逐题产出）。
- 答疑：``_tutor_generate`` / ``tutor_stream``（逐 token 讲解文本）。
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
from typing import Any, AsyncIterator, Literal

from pydantic import BaseModel

from app.ai import debug_log
from app.ai.engine import EngineResolution, resolve_engine
from app.ai.subagents.question import expand_specs
from app.domain.provider import GeneratedQuestion
from app.domain.retriever import build_retriever
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


# ───────────────────────── 出题流式 chunk 信封（ADR-0017） ─────────────────────────
# 对齐 AG-UI 的 BaseEvent.type 多态约定：每个 chunk 是一个带 `type` 判别字段的 JSON 对象，
# 取代原「裸 QuestionOut」chunk。传输帧（message/result/error）不变。
# - STEP：每题进度锚点
# - REASONING：出题推理增量（打底路径整段一次性下发，前端打字机揭示；reasoning 模型走 token 真流式）
# - CARD：成品题卡（QuestionOut.model_dump()）
class TaskGenStepChunk(BaseModel):
    type: Literal["STEP"] = "STEP"
    q_index: int
    label: str  # "正在为《数学》三年级「分数」出选择题…"


class TaskGenReasoningChunk(BaseModel):
    type: Literal["REASONING"] = "REASONING"
    q_index: int
    delta: str  # 推理增量


class TaskGenCardChunk(BaseModel):
    type: Literal["CARD"] = "CARD"
    q_index: int
    question: dict  # QuestionOut.model_dump()


TaskGenChunk = TaskGenStepChunk | TaskGenReasoningChunk | TaskGenCardChunk


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


def _build_stream_prompt(
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
) -> str:
    """单调用流式 prompt（ADR-0017 修订）：同一文本流里先后产出「推理」与「题卡 JSON」。

    模型先以 <reasoning>…</reasoning> 写出出题思路（后端逐 token 下发 REASONING，客户端
    实时可见，消除 5s 静默 + 推理闪现），随后输出 JSON 题卡。整段只需一次模型调用，
    成本较「推理 + 出题」两阶段减半。JSON 只含可变字段，subject/grade/知识点/题型/难度
    由调用方按 spec 回填，降低模型出错面。
    """
    clause = _build_question_clause(
        subject=subject, grade=grade, knowledge_point=knowledge_point,
        qtype=qtype, difficulty=difficulty, interests=interests, focus_interest=focus_interest,
    )
    if persona_hint:
        clause += f"\n\n{persona_hint}"
    if rag_context:
        clause += f"\n\n参考教材口径（仅作对齐参考，不照搬）：\n{rag_context}"
    return (
        clause + "\n\n"
        "请严格按以下两步顺序输出，两步之间不要加任何其他说明文字：\n"
        "1) 先用 1-3 句纯文本写出你的出题思路（情境如何选取、干扰项/答案如何设计、难度如何把控，"
        "纯学习相关），并用 <reasoning> 和 </reasoning> 包裹。\n"
        "2) 紧接着另起一行，只输出这道题的 JSON（不要 markdown 代码块围栏、不要任何额外文字），"
        '字段为：{"stem": str, "options": list[str]|null, "answer": str, '
        '"explanation": str, "reasoning": str}\n'
        "（reasoning 字段与上面的出题思路保持一致即可）"
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

    ``generate_question``（一次性结构化输出）与 ``generate_questions_stream``
    （流式文本 JSON 解析）共用同一「抽取字段 → 安全校验 → 构造题卡」逻辑，
    消除两套口径漂移（ADR-0023 决策 4）。

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


async def tutor_stream(
    engine: EngineResolution,
    *,
    grade: int,
    subject: str,
    knowledge_point: str,
    context: str | None,
    question: str,
) -> AsyncIterator[str]:
    """答疑流式：先做知识库检索注入 context，再逐 token 产出讲解文本。"""
    retriever = build_retriever()
    ctx = f"\n相关上下文：{context}" if context else ""
    if retriever is not None:
        chunks = retriever.retrieve(
            subject=subject, grade=grade, knowledge_point=knowledge_point, query=question
        )
        if chunks:
            kb = "\n".join(f"- {c.content}" for c in chunks)
            ctx = f"{ctx}\n\n【知识库】\n{kb}".strip()
    text = await _tutor_generate(
        engine, grade=grade, subject=subject,
        knowledge_point=knowledge_point, context=ctx, question=question,
    )
    yield text


async def generate_questions_stream(
    engine: EngineResolution,
    *,
    specs: list[Any],
    interests: list[str] | None = None,
    focus_interests: list[str] | None = None,
    rag_contexts: dict[int, str] | None = None,
    persona_hints: dict[int, str] | None = None,
) -> AsyncIterator[TaskGenChunk]:
    """出题流式：逐题产出信封 chunk（STEP → REASONING → CARD），题卡逐张浮现。

    每题**单次** generate_stream 调用：同一文本流里先 <reasoning>…</reasoning>（逐 token
    下发 REASONING，模型思考时客户端即可看到出题思路，消除结构化生成的 5s 静默 + 推理闪现），
    随后 JSON 题卡（完成即增量解析、解析成功才发 CARD）。无需「推理/出题」两次模型调用。
    每题都经 check_output 通过后才发 CARD。

    ADR-0021：``rag_contexts`` / ``persona_hints`` 由出题 SubAgent 按 q_index 预计算后传入，
    flow 只负责「按给定增强参数出题 + 安全闸门」，业务判断不在此处（不传则行为完全不变）。
    """
    n_focus = len(focus_interests) if focus_interests else 0
    items = expand_specs(specs)
    for q_index, it in enumerate(items):
        subject = it["subject"]
        grade = it["grade"]
        knowledge_point = it["knowledge_point"]
        qtype = it["qtype"]
        difficulty = it["difficulty"]
        focus = focus_interests[q_index % n_focus] if n_focus else None
        yield TaskGenStepChunk(
            q_index=q_index,
            label=_step_label(subject, grade, knowledge_point, qtype),
        )
        rag_ctx = (rag_contexts or {}).get(q_index)
        persona_hint = (persona_hints or {}).get(q_index)
        try:
            # 单次 generate_stream 调用：同一文本流里先 <reasoning>…</reasoning>（实时下发），
            # 随后 JSON 题卡（完成即解析下发）。无需「推理/出题」两次调用，成本减半。
            stream_prompt = _build_stream_prompt(
                subject=subject, grade=grade, knowledge_point=knowledge_point,
                qtype=qtype, difficulty=difficulty, interests=interests,
                focus_interest=focus, rag_context=rag_ctx, persona_hint=persona_hint,
            )
            sresp = engine.genkit.generate_stream(
                model=engine.model, system=_QUESTION_SYSTEM_PROMPT, prompt=stream_prompt,
            )
            buf = ""
            reasoning_parts: list[str] = []
            json_buf = ""
            phase: Literal["reasoning", "json"] = "reasoning"
            open_seen = False
            emitted = 0
            async for schunk in sresp.stream:
                t = _chunk_text(schunk)
                if not t:
                    continue
                buf += t
                if phase == "reasoning":
                    if not open_seen:
                        oi = buf.find("<reasoning>")
                        oj_pre = buf.find("{")
                        if oi == -1 and oj_pre == -1:
                            continue  # 等待开标签或 JSON 起始
                        if oi != -1 and (oj_pre == -1 or oi < oj_pre):
                            # 正常：先出现 <reasoning> 开标签。
                            open_seen = True
                            emitted = oi + len("<reasoning>")
                        else:
                            # 模型未用标签直接输出 JSON：{ 之前的文本当作推理。
                            if oj_pre > 0:
                                delta = buf[:oj_pre]
                                reasoning_parts.append(delta)
                                yield TaskGenReasoningChunk(q_index=q_index, delta=delta)
                            phase = "json"
                            json_buf = buf[oj_pre:]
                            continue
                    ci = buf.find("</reasoning>", emitted)
                    oj = buf.find("{", emitted)
                    if ci != -1 and (oj == -1 or ci < oj):
                        # 推理段结束：发出残余推理，进入出题段。
                        if ci > emitted:
                            delta = buf[emitted:ci]
                            reasoning_parts.append(delta)
                            yield TaskGenReasoningChunk(q_index=q_index, delta=delta)
                        phase = "json"
                        json_buf = buf[ci + len("</reasoning>"):]
                    elif oj != -1:
                        # 模型未用标签直接出 JSON：{ 之前当作推理。
                        if oj > emitted:
                            delta = buf[emitted:oj]
                            reasoning_parts.append(delta)
                            yield TaskGenReasoningChunk(q_index=q_index, delta=delta)
                        phase = "json"
                        json_buf = buf[oj:]
                    else:
                        # 仍在推理段：发出「安全前缀」（保留末尾可能的部分标签）。
                        safe = buf.rfind("<", emitted)
                        if safe == -1:
                            safe = len(buf)
                        if safe > emitted:
                            delta = buf[emitted:safe]
                            reasoning_parts.append(delta)
                            yield TaskGenReasoningChunk(q_index=q_index, delta=delta)
                            emitted = safe
                else:
                    json_buf += t
            await sresp.response
            parsed = _parse_question_json(json_buf)
            if parsed is None:
                raise ValueError("无法从模型输出解析出题目 JSON")
            reasoning_text = "".join(reasoning_parts).strip()
        except Exception:
            # 真实引擎单题失败（网络/限流/解析异常）：回退确定性 mock 题，
            # 保证流式不中断、末帧 result 仍正常发出，避免前端收到
            # "stream finished without a final result chunk"。
            q = _mock_question(
                subject=subject, grade=grade, knowledge_point=knowledge_point,
                qtype=qtype, difficulty=difficulty, interests=interests, focus_interest=focus,
            )
            if q.reasoning:
                yield TaskGenReasoningChunk(q_index=q_index, delta=q.reasoning)
            yield TaskGenCardChunk(q_index=q_index, question=q.model_dump())
            continue
        out_q = _assemble_question(
            raw=parsed,
            subject=subject,  # spec 回填（模型只需出可变字段，降低出错面）
            grade=grade,
            knowledge_point=knowledge_point,
            qtype=qtype,
            difficulty=difficulty,
            reasoning=reasoning_text,
        )
        if out_q is None:
            continue
        yield TaskGenCardChunk(q_index=q_index, question=out_q.model_dump())

