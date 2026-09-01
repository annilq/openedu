"""Genkit 流式 flow（ADR-0015 修订 / 迁移 08b：统一 Genkit 全栈）。

- 答疑：文本逐字（先缓冲 → check_output 通过 → 分块释放，守 ADR-008 不闪现违规片段）。
- 出题：逐题结构化产出（题卡逐张浮现），每题经 check_output 通过后才 send_chunk。
- 前后端统一协议：flow 经 `genkit_fastapi.handle_genkit_request` 以原生 action 端点暴露，
  前端用 `package:genkit/client.dart` 的 `defineRemoteAction` 直连（见迁移文档）。
- Mock = flow 内「一次性模拟数据源」分支：resolve_engine 返回 None（无 key / LLM_PROVIDER=mock）
  时直接产出确定性假数据，零外部依赖仍跑通闭环（原 MockProvider 逻辑已并入此处）。

安全层复用 domain/safety；genkit 仅在本文件（app/ai 边界）import。
"""
from __future__ import annotations

import hashlib
import random
from typing import Any, AsyncIterator, Literal

from genkit import ActionRunContext, Genkit
from pydantic import BaseModel
from sqlmodel import Session

from app.ai.engine import EngineResolution, resolve_engine
from app.core.db import engine as db_engine
from app.crud import add_tutor_usage, create_tutor_log
from app.domain.provider import GeneratedQuestion
from app.domain.retriever import build_retriever
from app.domain.safety import (
    SAFE_REFUSAL,
    check_output,
    tutor_system_prompt,
)
from app.models import User

# 单一 flow 宿主实例：仅用于注册 / 暴露 flow；实际模型调用由 resolve_engine 拿到的引擎执行。
# （Genkit flow 必须绑定在某个 Genkit 实例的 registry 上；宿主无需插件，生成走解析出的引擎。）
ai = Genkit()

# ───────────────────────── 输入 / 输出 schema（与前端点对齐） ─────────────────────────
class TutorAskInput(BaseModel):
    subject: str
    grade: int
    knowledge_point: str = ""
    context: str | None = None
    question: str
    model: str | None = None


class TutorReply(BaseModel):
    text: str = ""
    blocked: bool = False
    reason: str | None = None


class TaskSpecIn(BaseModel):
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    difficulty: str = "medium"
    count: int = 1


class TaskGenInput(BaseModel):
    child_id: str | None = None
    specs: list[TaskSpecIn]
    focus_interest: list[str] | None = None
    model: str | None = None


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
        '{"stem": str, "options": list[str]|null, "answer": str, "explanation": str, '
        '"reasoning": str}'
        '（reasoning 为本题的出题推理过程：简述情境选取、干扰项/答案设计思路、难度控制，'
        '约 1-3 句；纯学习相关）'
    )


def _schema_field(obj: Any, name: str, default: Any = None) -> Any:
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


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
) -> GeneratedQuestion | None:
    """非流式出题（落库路径）：复用流式同款 prompt + 安全闸门。

    返回 GeneratedQuestion；若真实模型产出不安全（check_output 未过）返回 None，
    由调用方回退（落库路径回退 mock，保证不落库违规内容且题量不丢）。
    """
    prompt = _build_question_prompt(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        difficulty=difficulty, interests=interests, focus_interest=focus_interest,
    )
    resp = await engine.genkit.generate(
        model=engine.model, system=_QUESTION_SYSTEM_PROMPT, prompt=prompt,
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
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        stem=stem, options=options, answer=answer, explanation=explanation, difficulty=difficulty,
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
) -> dict:
    """开放题批改（非流式路径）：有真实引擎走 Genkit，否则确定性 mock 启发式。

    统一单栈后替代原 LangChainProvider.grade_open；question 为 ORM Question
    （含 .stem/.knowledge_point/.explanation）。mock 分支按知识点关键词包含判定，
    保证零 key 也能批改（沿用原 MockProvider.grade_open 语义）。
    """
    if engine is None:
        engine = resolve_engine()
    if engine is None:
        correct = bool(student_answer) and any(
            kw in (student_answer or "") for kw in (question.knowledge_point,)
        )
        return {
            "correct": correct,
            "score": 1.0 if correct else 0.0,
            "explanation": question.explanation or "已收到作答。",
        }
    prompt = (
        f"题目：{question.stem}\n学生作答：{student_answer}\n"
        '请批改并返回 JSON：{"correct": bool, "score": float, "explanation": str}'
    )
    resp = await engine.genkit.generate(
        model=engine.model, system=_QUESTION_SYSTEM_PROMPT, prompt=prompt,
        output_schema=GradeSchema,
    )
    raw = resp.output
    return {
        "correct": bool(_schema_field(raw, "correct", False)),
        "score": float(_schema_field(raw, "score", 0.0)),
        "explanation": _schema_field(raw, "explanation", "")
        or (question.explanation or ""),
    }


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


def _extract_reasoning_token(chunk: Any) -> str | None:
    """尽力从 Genkit 流式 chunk 中提取思维链 token（reasoning 模型升级路径，ADR-0017）。

    不同提供方位置不一：有的在顶层 `reasoning`，有的在 `output`/`delta` 嵌套里。
    取不到（绝大多数非推理模型）返回 None，由调用方回退到结构化 `reasoning` 字段打底。
    """
    if chunk is None:
        return None
    top = getattr(chunk, "reasoning", None)
    if isinstance(top, str) and top:
        return top
    out = getattr(chunk, "output", None)
    if isinstance(out, dict):
        r = out.get("reasoning")
        if isinstance(r, str) and r:
            return r
    return None


async def generate_questions_stream(
    engine: EngineResolution,
    *,
    specs: list[Any],
    interests: list[str] | None = None,
    focus_interests: list[str] | None = None,
) -> AsyncIterator[TaskGenChunk]:
    """出题流式：逐题产出信封 chunk（STEP → REASONING → CARD），题卡逐张浮现。

    每题经 check_output 通过后才发 CARD；REASONING 在 CARD 到达前作为内联推理区下发
    （reasoning 模型走 token 真流式，否则用结构化 `reasoning` 字段打底）。
    """
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
            q_index = idx
            idx += 1
            yield TaskGenStepChunk(
                q_index=q_index,
                label=_step_label(subject, grade, knowledge_point, qtype),
            )
            prompt = _build_question_prompt(
                subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
                difficulty=difficulty, interests=interests, focus_interest=focus,
            )
            try:
                sr = engine.genkit.generate_stream(
                    model=engine.model, system=_QUESTION_SYSTEM_PROMPT, prompt=prompt,
                    output_schema=QuestionSchema,
                )
                reasoning_parts: list[str] = []
                async for chunk in sr.stream:
                    token = _extract_reasoning_token(chunk)
                    if token:
                        reasoning_parts.append(token)
                        yield TaskGenReasoningChunk(q_index=q_index, delta=token)
                # 注意：Genkit 流式 .response 是 ModelResponse，结构化输出在 .output
                # （QuestionSchema 实例），不在响应对象自身——直接 .stem 会 AttributeError。
                result = await sr.response
                parsed = result.output
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
            # 打底：若未走 reasoning token 流（非推理模型），用结构化 reasoning 字段补一发。
            if not reasoning_parts and parsed.reasoning:
                yield TaskGenReasoningChunk(q_index=q_index, delta=parsed.reasoning)
            verdict = check_output(f"{parsed.stem} {parsed.answer} {parsed.explanation}")
            if not verdict.safe:
                continue
            out_q = QuestionOut(
                subject=parsed.subject,
                grade=parsed.grade,
                knowledge_point=parsed.knowledge_point,
                qtype=parsed.qtype,
                stem=parsed.stem,
                options=parsed.options,
                answer=parsed.answer,
                explanation=parsed.explanation,
                difficulty=parsed.difficulty,
                reasoning=parsed.reasoning,
            )
            yield TaskGenCardChunk(q_index=q_index, question=out_q.model_dump())


# ───────────────────────── Genkit flow（前后端统一协议端点） ─────────────────────────
def _release_text(ctx: ActionRunContext, text: str, *, chunk_size: int = 12) -> None:
    """安全释放：check_output 已通过后，才分小块 send_chunk（打字机效果，违规片段从不外发）。"""
    for i in range(0, max(len(text), 1), chunk_size):
        ctx.send_chunk(text[i : i + chunk_size])


@ai.flow(chunk_type=str)
async def tutor_ask(input: TutorAskInput, ctx: ActionRunContext) -> TutorReply:
    """娃娃答疑流式 flow：先生成并整体校验，再分块释放；mock 模式走模拟数据源。"""
    auth = ctx.context or {}
    child_id = auth.get("child_id")

    # 与 tasks_generate 一致：带 session 解析模型，避免 ModelConfig 自定义模型回退 mock。
    engine = None
    with Session(db_engine) as s:
        engine = resolve_engine(input.model, parent_id=auth.get("parent_id"), session=s)
    if engine is None:
        text = _mock_tutor_text(
            grade=input.grade, subject=input.subject,
            knowledge_point=input.knowledge_point, context=input.context, question=input.question,
        )
    else:
        tokens: list[str] = []
        async for tok in tutor_stream(
            engine, grade=input.grade, subject=input.subject,
            knowledge_point=input.knowledge_point, context=input.context, question=input.question,
        ):
            tokens.append(tok)
        text = "".join(tokens)

    # 输出安全：整体校验通过才放量；违规 → 整段替换为安全兜底。
    if not check_output(text).safe:
        _release_text(ctx, SAFE_REFUSAL)
        _log_tutor(child_id, input, SAFE_REFUSAL, blocked=True)
        return TutorReply(text=SAFE_REFUSAL, blocked=True, reason="输出含敏感内容")

    _release_text(ctx, text)
    _log_tutor(child_id, input, text, blocked=False)
    return TutorReply(text=text, blocked=False)


@ai.flow(chunk_type=dict)
async def tasks_generate(input: TaskGenInput, ctx: ActionRunContext) -> list[dict]:
    """家长出题流式 flow：逐题产出，题卡逐张浮现；mock 模式走模拟数据源。

    流式块与末帧 result 均返回 JSON 原生 dict（QuestionOut.model_dump()），避免 Genkit
    SSE 序列化器对 pydantic 模型做 json.dumps 失败；前端 fromStreamChunk/fromResponse
    按 dict 解析为 QuestionPreview，契约不变。
    """
    auth = ctx.context or {}
    parent_id = auth.get("parent_id")
    child_id = input.child_id or auth.get("child_id")

    # 兴趣池：按 child_id 加载娃娃画像（避免与 tasks.py 交叉 import）。
    interests_pool: list[str] | None = None
    if child_id is not None:
        with Session(db_engine) as s:
            child = s.get(User, _as_uuid(child_id))
            if child is not None and child.interests:
                # User.interests 为 dict：{"categories": [...], "free_text": str}
                cat = child.interests.get("categories") or []
                pool = [c for c in cat if isinstance(c, str)]
                free = child.interests.get("free_text")
                if isinstance(free, str) and free.strip():
                    pool.append(free.strip())
                interests_pool = pool or None

    # 流式路径必须把 session 传给 resolve_engine，否则 ModelConfig 自定义模型分支
    # （engine.py 第 1 步）因缺 session 被跳过，回退到全局 LLM_PROVIDER → mock；
    # 同步 batch-generate 路径一直带 session，故二者行为曾不一致（预览返回 mock）。
    engine = None
    with Session(db_engine) as s:
        engine = resolve_engine(input.model, parent_id=parent_id, session=s)
    focus = input.focus_interest or []
    out: list[dict] = []

    if engine is None:
        idx = 0
        for sp in input.specs:
            for _ in range(max(0, sp.count)):
                f = focus[idx % len(focus)] if focus else None
                q = _mock_question(
                    subject=sp.subject, grade=sp.grade, knowledge_point=sp.knowledge_point,
                    qtype=sp.qtype, difficulty=sp.difficulty, interests=interests_pool, focus_interest=f,
                )
                # 信封 chunk：STEP → REASONING → CARD（对齐 ADR-0017）。
                # 信封 chunk：STEP → REASONING → CARD（对齐 ADR-0017）。
                ctx.send_chunk(
                    TaskGenStepChunk(
                        q_index=idx,
                        label=_step_label(sp.subject, sp.grade, sp.knowledge_point, sp.qtype),
                    ).model_dump()
                )
                if q.reasoning:
                    ctx.send_chunk(
                        TaskGenReasoningChunk(q_index=idx, delta=q.reasoning).model_dump()
                    )
                ctx.send_chunk(
                    TaskGenCardChunk(q_index=idx, question=q.model_dump()).model_dump()
                )
                out.append(q.model_dump())
                idx += 1
        return out

    async for chunk in generate_questions_stream(
        engine, specs=list(input.specs), interests=interests_pool, focus_interests=focus,
    ):
        # generate_questions_stream 已产出信封 chunk（STEP/REASONING/CARD）；
        # 仅把 CARD 的题卡收进末帧 result，REASONING/STEP 不进 result（纯流式 UX）。
        if isinstance(chunk, TaskGenCardChunk):
            out.append(chunk.question)
        ctx.send_chunk(chunk.model_dump())
    return out


def _as_uuid(value: object) -> Any:
    import uuid

    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError, AttributeError):
        return None


def _log_tutor(child_id: Any, input: TutorAskInput, answer: str, *, blocked: bool) -> None:
    """答疑用量 / 日志落库（flow 内，因流式在此结束）。"""
    if child_id is None:
        return
    cid = _as_uuid(child_id)
    if cid is None:
        return
    try:
        with Session(db_engine) as s:
            add_tutor_usage(session=s, child_id=cid, seconds=0)
            create_tutor_log(
                session=s, child_id=cid, grade=input.grade, subject=input.subject,
                knowledge_point=input.knowledge_point, question=input.question,
                answer=answer, input_safe=True, output_safe=not blocked, blocked=blocked,
            )
    except Exception:
        # 日志失败不应打断流式响应
        pass
