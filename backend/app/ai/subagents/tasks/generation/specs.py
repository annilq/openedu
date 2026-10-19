"""出题规格与编排件（ADR-0097 从 agent.py 拆出）。

拆出的理由：``tools/generate_questions``（流式 tool）要复用这里的编排函数，
而 ``agent.py`` 要 import tools 注册表——函数留在一处就会成环。故 specs/prompt
组装/上下文计算归本模块，agent 与 tool 都从这取。
"""
from __future__ import annotations

from typing import Any

from app.ai.subagents.tasks.generation.pipeline import (
    build_question_prompts,
    step_label,
    stream_question,
)
from app.ai.subagents.tasks.generation.translate import translate_stream
from app.ai.subagents.subject_personas import get_subject_persona
from app.domain.spec_keywords import (
    CN_NUM,
    COUNT_CN_RE,
    COUNT_RE,
    GRADE_CN_RE,
    GRADE_RE,
    QTYPE_KEYWORDS,
    SUBJECT_ALIASES,
)
from app.domain.subjects import SUBJECTS
from app.features.materials.figure_stamp import (
    available_figures,
    render_figure_catalog,
)
from app.features.materials.scene_fusion import find_knowledge_point


def figure_catalog_for_question(
    session,
    *,
    teacher_id,
    subject: str,
    grade: int,
    knowledge_point: str,
    semester: str = "",
) -> str | None:
    """本题「可用图形清单」渲染成 prompt 文本（ADR-0089 §4.3）；取不到 → ``None``。

    目录 = ``kp.scenes`` curated 图形优先 → 回落图库全量（``available_figures``）。
    只给 key + 中文名，**顶点绝不进 prompt**。无 session / 查询失败 → 不注入清单，
    出题照常（清单是增强，绝不阻断出题主链路）。
    """
    if session is None or teacher_id is None:
        return None
    try:
        kp = find_knowledge_point(
            session,
            teacher_id=teacher_id,
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            semester=semester,
        )
        catalog = render_figure_catalog(available_figures(session, kp=kp))
    except Exception:  # noqa: BLE001 — 目录是增强，任何异常都不阻断出题
        return None
    return catalog or None


def expand_specs(specs) -> list[dict]:
    """把 specs（dict 或对象）按 count 展开为「每题一条」列表（顺序即 q_index）。"""
    items: list[dict] = []
    for sp in specs:
        if isinstance(sp, dict):
            subject = str(sp.get("subject", ""))
            grade = int(sp.get("grade", 0))
            knowledge_point = str(sp.get("knowledge_point", ""))
            qtype = str(sp.get("qtype", ""))
            difficulty = str(sp.get("difficulty", "medium"))
            semester = str(sp.get("semester", ""))
            count = int(sp.get("count", 1))
            # 判断题标记（ADR-0072）：判断题闭环的规格带 judge=True，让题面为「陈述句 +
            # 对/错两个选项」；普通按规格出题不带，行为不变。
            judge = bool(sp.get("judge", False))
            multi = bool(sp.get("multi", False))
        else:
            subject = str(sp.subject)
            grade = int(sp.grade)
            knowledge_point = str(sp.knowledge_point)
            qtype = str(sp.qtype)
            difficulty = str(sp.difficulty)
            semester = str(getattr(sp, "semester", "") or "")
            count = int(sp.count)
            judge = bool(getattr(sp, "judge", False))
            multi = bool(getattr(sp, "multi", False))
        for _ in range(max(0, count)):
            items.append(
                {
                    "subject": subject,
                    "grade": grade,
                    "knowledge_point": knowledge_point,
                    "qtype": qtype,
                    "difficulty": difficulty,
                    "semester": semester,
                    "judge": judge,
                    "multi": multi,
                }
            )
    return items


def build_prompt_from_specs(specs) -> list[dict]:
    """结构化出题规格 → 内部 per-question 项列表（按 count 展开，顺序即 q_index）。

    这是 ADR-0034 Phase 1 的「通过结构化参数构造 prompt」接缝：规格在此直接规整为
    内部表示，驱动逐题 prompt 构造，取代原先「自由文本 → 正则解析」的有损通路。
    ``specs`` 元素是 dict 或带 subject/grade/knowledge_point/qtype/difficulty/count
    属性的对象。
    """
    return expand_specs(specs)


def build_question_context(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    query: str | None,
    retriever=None,
) -> tuple[str | None, str, list[dict]]:
    """计算 ``(rag_context, persona_hint, source_refs)``：RAG 命中 + Persona + 溯源快照。

    ``source_refs`` 是 ADR-0055 §10 的快照溯源：``[{material: 资料名, snippet: 摘要}]``，
    随题卡下发并随题落库——资料删除后题目依据仍在（不建外键的原因）。
    rag_context 每行带【资料名】前缀，让模型知道口径来自哪份资料（仅作对齐参考）。
    """
    rag_context: str | None = None
    source_refs: list[dict] = []
    if retriever is not None and (knowledge_point or query):
        chunks = retriever.retrieve(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            query=query or knowledge_point,
        )
        if chunks:
            lines = []
            for c in chunks:
                if c.source_name:
                    source_refs.append(
                        {"material": c.source_name, "snippet": c.content[:80]}
                    )
                    lines.append(f"- 【{c.source_name}】{c.content}")
                else:
                    lines.append(f"- {c.content}")
            rag_context = "\n".join(lines)
    persona_hint = get_subject_persona(subject).render()
    return rag_context, persona_hint, source_refs


def parse_specs_from_text(text: str) -> list[dict]:
    """从自由文本解析出题规格（悬浮助手一句话出题）。

    识别：科目（标准名/别名）、年级（数字/中文+年级）、数量（N道/题）、题型。
    识别不到时返回空列表（由调用方提示用户补充）。数量上限 5 防滥用。
    """
    import re

    specs: list[dict] = []

    subject = ""
    for alias, std in SUBJECT_ALIASES.items():
        if alias in text:
            subject = std
            break
    if not subject:
        for s in SUBJECTS:
            if s in text:
                subject = s
                break

    grade = 0
    m = GRADE_RE.search(text)
    if m:
        grade = int(m.group(1))
    else:
        m = GRADE_CN_RE.search(text)
        if m:
            grade = CN_NUM.get(m.group(1), 0)

    count = 1
    m = COUNT_RE.search(text)
    if m:
        count = min(int(m.group(1)), 5)
    else:
        m = COUNT_CN_RE.search(text)
        if m:
            count = min(CN_NUM.get(m.group(1), 1), 5)

    qtype = "choice"
    for kw, qt in QTYPE_KEYWORDS.items():
        if kw in text:
            qtype = qt
            break

    # 多选题标记（ADR-0004 D5）：自然语言里出现「多选 / 多选题」即视为多选，
    # 与 QTYPE_KEYWORDS 把「多选」映射到 choice 相互独立——多选题仍是 choice 题型，
    # 只是 multi=True，渲染为复选、批改按集合比对。
    multi = "多选" in text or "多选题" in text

    # 判断题标记（ADR-0089）：自然语言出现「判断题 / 判断对错 / 判断正误」即视为
    # 判断题，由出题子代理自主产出 judge 规格（不再经服务端信号归一化与 quiz_generate
    # 动作键）。题面为「陈述句 + 对/错两个选项」，题卡含答案原样落对话历史、前端隐藏待揭示。
    judge = "判断题" in text or "判断对错" in text or "判断正误" in text

    kp = ""
    m = re.search(r"关于\s*《?\s*([\u4e00-\u9fa5A-Za-z0-9]+)", text)
    if m:
        kp = m.group(1)
    else:
        qt_kw = next((kw for kw, _ in QTYPE_KEYWORDS.items() if kw in text), None)
        if subject and qt_kw:
            between = text.split(subject, 1)[-1].split(qt_kw, 1)[0]
            candidate = re.sub(r"[关于的\s]+", "", between)
            candidate = re.sub(r"\d\s*年级|[一二三四五六七八九]\s*年级", "", candidate)
            if re.search(r"[\u4e00-\u9fa5]", candidate):
                kp = candidate

    if subject:
        specs.append(
            {
                "subject": subject,
                "grade": grade,
                "knowledge_point": kp,
                "qtype": qtype,
                "difficulty": "medium",
                "semester": "",
                "count": count,
                "multi": multi,
                "judge": judge,
            }
        )
    return specs


def merge_spec_layers(base: list, overrides: list) -> list[dict]:
    """把「已确认规格」（base）与「模型 args 规格」（overrides）合成一份。

    **合并而非拼接**（ADR-0099）：旧实现把两条来源 append 成列表再各自展开，
    注入持久规格后模型若仍按历史填 args，count 会相加（「再出 2 道」变 4 道）。
    这里 base 作基底、overrides 只覆盖自身**有值**的字段——既保住「结构化规格
    优先、不让模型改写」（ADR-0095），又让模型表达的新意图（换难度 / 换题型）生效。

    ``overrides`` 中缺省（缺席编码）的字段不参与覆盖：``qtype`` 取 ``""`` / ``count``
    取 ``0`` 等值由调用方先行归一为「未提供」（见 ``_spec_from_args``）。
    """
    if not overrides:
        return list(base)
    if not base:
        return list(overrides)
    # 单规格场景（slot filling 一次只产出一份）：基底取首份，其余保持在后。
    merged = dict(base[0]) if isinstance(base[0], dict) else base[0]
    layered = dict(overrides[0]) if isinstance(overrides[0], dict) else overrides[0]
    out = {**merged}
    for key, value in layered.items():
        if value in (None, "", 0, False):
            continue
        out[key] = value
    return [out, *base[1:]]


def specs_from_context(specs, *, ctx: Any) -> list[dict]:
    """规格解析的完整入口：结构化 specs 优先，课件上下文回填，正则兜底。

    顺序即优先级：

    1. ``ctx.extra["specs"]``（ADR-0095 slot filling 备好的结构化规格，等值直配
       ``task_generate`` 与预检完整轮都走这条）——绝不过自然语言；
    2. 课件 / 知识点下钻透传的 ``ctx.extra``（subject / grade / courseware）——
       用户点「出一道判断题」按钮时无需再敲科目年级；
    3. ``parse_specs_from_text`` 正则兜底（message 已由 tool loop 首轮交给模型，
       走到这里说明模型没填参，只能从原文再捞一次）。

    三条路径统一经 ``expand_specs`` 展开（count → 每题一项）——正则与课件回填
    产出的是 spec 列表，漏展开会把「2 道」静默变成 1 道（曾据此红过一轮）。
    """
    if specs:
        return build_prompt_from_specs(specs)
    message = (ctx.message or "").strip() if ctx else ""
    parsed = parse_specs_from_text(message)
    if not parsed:
        extra_subject = str((ctx.extra if ctx else {}).get("subject") or "")
        if extra_subject:
            cw = (ctx.extra or {}).get("courseware") or {}
            kp_name = str(cw.get("knowledge_point") or "") if isinstance(cw, dict) else ""
            parsed.append(
                {
                    "subject": extra_subject,
                    "grade": int((ctx.extra or {}).get("grade") or 0),
                    "knowledge_point": kp_name,
                    "qtype": "choice",
                    "difficulty": "medium",
                    "semester": "",
                    "count": 1,
                    "multi": False,
                    "judge": (
                        "判断题" in message
                        or "判断对错" in message
                        or "判断正误" in message
                    ),
                }
            )
    return expand_specs(parsed)


def with_skills(persona_hint: str, skills: str) -> str:
    """把业务 SOP（ADR-0030：manifest 声明的 skills/*.md 全文）拼到学科 Persona 之后。"""
    sop = (skills or "").strip()
    return f"{persona_hint}\n\n{sop}" if sop else persona_hint


def subject_summary(items: list[dict]) -> str:
    """多学科一卷的学科概览：``数学 1 道、语文 1 道``；单学科返回空串。

    ADR-0097：随 ToolOutcome 回灌给收尾轮的模型——多学科不得只报第一科的
    学科名（旧实现取 ``items[0].subject`` 会说「已生成 2 道数学题」这种错话），
    该纪律从服务端文案转为「回灌数据 + system prompt 指令」双点守护。
    """
    order: list[str] = []
    tally: dict[str, int] = {}
    for it in items:
        s = it["subject"]
        if s not in tally:
            order.append(s)
            tally[s] = 0
        tally[s] += 1
    if len(order) < 2:
        return ""
    return "、".join(f"{s} {tally[s]} 道" for s in order)
