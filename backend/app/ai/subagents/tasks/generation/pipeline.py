"""出题管线（prompt 组装 → provider 流式 → 语义事件）。

本模块是**出题业务的完整管线**，原归属 question 子包（ADR-0032 Q3：原
``app/ai/generation.py`` 的教育出题内容归位到子代理），ADR-0098 随 question 域
并入迁至 ``tasks/generation/``（``app/ai`` 只留 genkit/DB 桥接）：

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
from app.ai.subagents.tasks.generation.parsers import (
    QuestionListSchema,
    QuestionOut,
    QuestionSchema,
    QuestionSpec,
    assemble_question,
    assemble_questions,
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


def batch_step_label(
    subject: str, grade: int, knowledge_point: str, qtype: str, count: int
) -> str:
    """批量进度标签（STEP 帧）：``正在为《数学》3年级「分数」出 5 道选择题…``。

    ``count==1`` 时与 :func:`step_label` 逐字一致——单题请求仍走单题路径，
    进度文案不该因为走哪条路而变。
    """
    if count <= 1:
        return step_label(subject, grade, knowledge_point, qtype)
    return (
        f"正在为《{subject}》{grade}年级「{knowledge_point}」"
        f"出 {count} 道{qtype_label(qtype)}…"
    )


def _build_question_clause(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    semester: str,
    count: int = 1,
    multi: bool = False,
    judge: bool = False,
) -> str:
    """出题语境内核（情境/难度/兴趣包装）：流式与落库共用，保证口径一致
    （ADR-0021：RAG / 学科 Persona 在调用方注入）。

    ``count`` 为这一批的题数（1 = 单题）。批量时额外要求逐题异构——否则模型一次性
    产出 N 道题时会把同一道题换个数字重出 N 遍，那比逐题串行调用还糟。
    """
    sem_hint = f"{semester}" if semester else "整学年"
    how_many = f"{count}道" if count > 1 else "一道"
    clause = (
        f"请为{grade}年级《{subject}》（{sem_hint}）的“{knowledge_point}”"
        f"出{how_many}{qtype}题，难度{difficulty}。"
    )
    if count > 1:
        clause += (
            f"这 {count} 道题必须彼此不同：题干的情境、已知条件与答案都要换，"
            "考查角度互补（不要只是把数字改一改），否则等于只出了一道题。"
        )
    # 多选题提示（ADR-0004 D5）：正确答案可能不止一个，answer 用「｜」连接所有
    # 正确选项的**完整文本**（与 options 中某一行完全一致），例如「苹果｜香蕉」。
    if multi:
        clause += (
            "这是一道多选题，正确答案可能不止一个；请在 options 中给出全部备选项，"
            "并在 answer 字段填写所有正确选项的完整文本，多个正确项用「｜」连接"
            "（例如「苹果｜香蕉」），不要只写一个字母。"
        )
    # 数学客观题答案格式约束（ADR-0071）：降低标准答案歧义，让数值解析更稳定。
    # 仅提示、不强制——模型不守时仍走原 assemble_question 安全闸门与落库流程，不破坏出题链路。
    if subject == "数学" and qtype in ("fill", "calc"):
        clause += (
            "这是数学填空/计算题，请在 answer 字段只填「纯数值」或「数值+标准单位」"
            "（如 12、12厘米、0.12米、3/4），分数用 a/b 形式（如 1/2），"
            "不要写单位换算过程或多余说明；若有多解用「或」分隔（如 12或15）。"
        )
    # 判断题（ADR-0072 闭环）：强制「陈述句题干 + 仅两个选项『对』『错』」，
    # answer 填『对』或『错』，让后端确定性判定用户自然语言 yes/no。
    if judge:
        clause += (
            "这是一道**判断题**：题干应为一个陈述句（如「平行四边形是轴对称图形」），"
            "请只给出两个选项，分别为「对」和「错」（不要加 A./B. 等前缀），"
            "并在 answer 字段填写「对」或「错」（按该陈述是否正确）。"
            "不要给出除这两个选项以外的答案变体。"
        )
    return clause


def _build_question_prompt(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    semester: str = "",
    count: int = 1,
    rag_context: str | None = None,
    persona_hint: str | None = None,
    history: list[dict] | None = None,
    weak_examples: list[dict] | None = None,
    multi: bool = False,
    judge: bool = False,
    figure_catalog: str | None = None,
) -> str:
    """出题 prompt（流式与落库**同一份**，模型产出受 ``QuestionSchema`` 约束）。"""
    clause = _build_question_clause(
        subject=subject, grade=grade, knowledge_point=knowledge_point,
        qtype=qtype, difficulty=difficulty, semester=semester,
        count=count, multi=multi, judge=judge,
    )
    if persona_hint:
        clause += f"\n\n{persona_hint}"
    # 图形化选项（ADR-0089 §4.3）：把「可用图形清单」注入 prompt，模型只填**身份键**。
    # 顶点绝不出现（模型编不出正确坐标，几何由后端从图库盖章）。
    if figure_catalog:
        clause += (
            "\n\n如果本题的选项可以用平面图形表示（例如「下列图形哪些是轴对称图形」），"
            "请为**每个**选项都填 `figure_key`，只能从下面的可用图形清单里选；"
            "**不要输出任何顶点坐标**。若并非每个选项都有合适的图形，就整题都不填"
            "（要么全有、要么全无）。可用图形清单（key — 中文名）：\n"
            f"{figure_catalog}"
        )
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
    # ADR-0060 D4：同类题仿写——把该学生此前做错的同类题作为样例塞进 prompt，
    # 让模型参考其考查角度与表述风格，出一道**全新**的同类题，而非凭空出题。
    # 这是「反馈边」廉价的实现：不引入向量检索/相似度算法，只把原题题干当上下文。
    # 仿写只作用于 AI 生成题（origin="ai"），不会把教师从教辅录入的题再繁衍（ADR-0020）。
    if weak_examples:
        samples = []
        for i, ex in enumerate(weak_examples[:3], 1):
            sample = (
                f"【错例 {i}】（{ex.get('qtype', '题')}，"
                f"知识点「{ex.get('knowledge_point', '')}」）\n题干：{ex.get('stem', '')}"
            )
            if ex.get("options"):
                sample += f"\n选项：{ex['options']}"
            if ex.get("answer"):
                sample += f"\n答案：{ex['answer']}"
            samples.append(sample)
        clause += (
            "\n\n以下是这个学生此前做错的同类题样例，仅供你参考其考查角度与常见表述，"
            "不要照抄或改写原题，而要据此出一道**全新的、同知识点同难度**的题，"
            "考查角度可与样例互补：\n" + "\n\n".join(samples)
        )
    tail = (
        "另外用 1-3 句写出你的出题思路（情境如何选取、干扰项/答案如何设计、难度如何把控，"
        "纯学习相关），填入 reasoning 字段。"
    )
    if count > 1:
        tail = (
            f"把 {count} 道题放进 questions 数组，每道题一个元素；"
            "每道题再用 1-3 句写出该题的出题思路（情境如何选取、干扰项/答案如何设计、"
            "难度如何把控，纯学习相关），填入该题的 reasoning 字段。"
        )
    return clause + "\n\n" + tail


def build_question_prompts(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    semester: str = "",
    count: int = 1,
    rag_context: str | None = None,
    persona_hint: str | None = None,
    history: list[dict] | None = None,
    weak_examples: list[dict] | None = None,
    multi: bool = False,
    judge: bool = False,
    figure_catalog: str | None = None,
) -> tuple[str, str, QuestionSpec]:
    """组装出题 prompt（ADR-0030 收口 #4：prompt 组装从 provider 搬到调用方）。

    返回 ``(system_prompt, user_prompt, spec)``：
    - ``system_prompt``：固定的出题系统约束（适龄 / JSON 输出）。
    - ``user_prompt``：情境 / 难度 / 兴趣 / RAG / Persona / 多轮历史拼装后的完整用户指令。
    - ``spec``：题目不可变身份（subject/grade/knowledge_point/qtype/difficulty/semester），
      由调用方给出、回填空模型产出（模型不一定回写这些字段）。

    出题 SubAgent（``agent.py``）与落库路径都经由此函数组装，再交给 provider；
    provider 接口从此只收「已组装 prompt + spec」，不再泄漏 9 个业务 kwarg。
    """
    user_prompt = _build_question_prompt(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        difficulty=difficulty, semester=semester, count=count,
        rag_context=rag_context,
        persona_hint=persona_hint, history=history, weak_examples=weak_examples,
        multi=multi, judge=judge, figure_catalog=figure_catalog,
    )
    spec = QuestionSpec(
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        difficulty=difficulty,
        semester=semester,
        multi=multi,
        judge=judge,
    )
    return QUESTION_SYSTEM_PROMPT, user_prompt, spec


def _card_from(out: QuestionOut) -> QuestionCard:
    """``QuestionOut`` → 题卡事件（单题与批量共用同一份装配，落库字段逐字一致）。"""
    return QuestionCard(
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
            semester=out.semester,
            multi=out.multi,
            judge=out.judge,
        ),
        reasoning=out.reasoning,
    )


async def stream_questions(
    provider: LLMProvider,
    *,
    system_prompt: str,
    user_prompt: str,
    spec: QuestionSpec,
    count: int,
    history: list[dict] | None = None,
) -> AsyncIterator[QuestionStreamEvent]:
    """批量流式出题：一次 ``provider.stream(schema=QuestionListSchema)`` 出一组同规格题。

    与 :func:`stream_question` 的差别只有两处：约束 schema 是数组、产出多张题卡。
    闸门仍是那一个（``assemble_questions`` 逐元素过），题面不过闸的整题丢弃、不影响
    同批其它题；全部不过闸才发 ``QuestionFailed``。

    **代价**（改用它前必须接受）：schema 路的 JSON 只在末帧整块到达，题卡因此不再
    逐题流出，而是一次性到齐。换来的省下的 N-1 次往返——本地小模型上逐题串行出 2 道
    实测 19-36 秒（提交 77f69134 为此把 SSE 超时抬到 10 分钟），批量后这部分时间是
    一次请求的时长。
    """
    if not getattr(provider, "configured", True):
        yield QuestionFailed(
            reason="未配置 AI 出题引擎，无法生成题目。请在「模型管理」中添加模型并设为默认后重试。"
        )
        return
    reasoning: list[str] = []
    async for ev in provider.stream(
        system_prompt, user_prompt, schema=QuestionListSchema, history=history
    ):
        if isinstance(ev, TextDelta):
            reasoning.append(ev.delta)
            yield ReasoningDelta(delta=ev.delta)
        elif isinstance(ev, StructuredDone):
            raw = coerce_dict(ev.data)
            raw_list = raw.get("questions")
            picked = raw_list if isinstance(raw_list, list) else []
            outs = assemble_questions(
                raw_list=[i for i in picked if isinstance(i, dict)],
                spec=spec,
                reasoning="".join(reasoning).strip(),
                limit=count,
            )
            if not outs:
                yield QuestionFailed(reason="生成内容未通过安全校验")
            else:
                for out in outs:
                    yield _card_from(out)
            return
    yield QuestionFailed(reason="模型未返回结构化题卡")


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
    # 引擎未配置：显式下发失败语义事件（而非静默空迭代），让上层给出准确提示，
    # 而不是误导用户「调整科目或年级」（mock / 未配 key 时科目年级根本没被用到）。
    if not getattr(provider, "configured", True):
        yield QuestionFailed(
            reason="未配置 AI 出题引擎，无法生成题目。请在「模型管理」中添加模型并设为默认后重试。"
        )
        return
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
                yield _card_from(out)
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
    semester: str = "",
    rag_context: str | None = None,
    persona_hint: str | None = None,
    history: list[dict] | None = None,
    multi: bool = False,
    judge: bool = False,
) -> GeneratedQuestion | None:
    """非流式出题（落库路径）：内部 drain ``stream_question`` 取题卡。

    返回 ``GeneratedQuestion``；模型未产出 / 产出不安全（安全闸门未过）返回 ``None``，
    由调用方抛 ``LLM_UNAVAILABLE``。全程只依赖 ``LLMProvider``（ADR-0032：不再直连 genkit 引擎）。
    """
    system_prompt, user_prompt, spec = build_question_prompts(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        difficulty=difficulty, semester=semester, rag_context=rag_context,
        persona_hint=persona_hint, history=history, multi=multi, judge=judge,
    )
    async for ev in stream_question(
        provider, system_prompt=system_prompt, user_prompt=user_prompt, spec=spec, history=history
    ):
        if isinstance(ev, QuestionCard):
            return ev.question
    return None
