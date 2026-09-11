"""出题 SubAgent（ADR-0024 / 文件夹化）：RAG + 学科 Persona 注入。

位于 ``app/ai/subagents/question/``，与本文件夹 ``manifest.py`` 一同被 AgentRuntime
发现并加载。统一契约：``run(message, ctx)`` 异步产出 AG-UI 事件帧（TOOL_CALL / STEP /
THINKING / DATA / TOOL_RESULT / ASSISTANT_MESSAGE），由 runtime 负责
USER_MESSAGE / 路由 THINKING / DONE 与持久化。

出题走**单调用流式**：每题先发 STEP 进度锚点，再把模型推理逐 token 转为 THINKING
增量，JSON 解析 + 安全闸门通过后发 DATA 题卡（ADR-0017 升级）。

本 subagent 是 ``agent_core`` 的「首个接入方」之一：只依赖 agent_core 的
``BaseSubAgent`` / ``SubAgentContext`` 与通用 ``LLMProvider.stream``；出题特有的
prompt 组装与解析就地在子包内完成（``pipeline.py`` / ``parsers.py``，ADR-0032 Q3）。
"""
from __future__ import annotations

from agent_core.protocol import step
from agent_core.subagent import BaseSubAgent, SubAgentContext
from app.ai.subagents.question.pipeline import (
    build_question_prompts,
    step_label,
    stream_question,
)
from app.ai.subagents.question.translate import translate_stream
from app.ai.subagents.subject_personas import get_subject_persona
from app.domain.quota import SUBJECTS


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
            count = int(sp.get("count", 1))
        else:
            subject = str(sp.subject)
            grade = int(sp.grade)
            knowledge_point = str(sp.knowledge_point)
            qtype = str(sp.qtype)
            difficulty = str(sp.difficulty)
            count = int(sp.count)
        for _ in range(max(0, count)):
            items.append(
                {
                    "subject": subject,
                    "grade": grade,
                    "knowledge_point": knowledge_point,
                    "qtype": qtype,
                    "difficulty": difficulty,
                }
            )
    return items


def build_prompt_from_specs(specs) -> list[dict]:
    """结构化出题规格 → 内部 per-question 项列表（按 count 展开，顺序即 q_index）。

    这是 ADR-0034 Phase 1 的「通过结构化参数构造 prompt」接缝：规格在此直接规整为
    内部表示，驱动 ``run`` 内逐题 prompt 构造，取代原先「自由文本 → 正则解析」的
    有损通路。``specs`` 元素是 dict 或带 subject/grade/knowledge_point/qtype/
    difficulty/count 属性的对象。
    """
    return expand_specs(specs)


def build_question_context(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    query: str | None,
    retriever=None,
) -> tuple[str | None, str]:
    """计算 ``(rag_context, persona_hint)``：RAG 命中 + 学科 Persona 渲染。"""
    rag_context: str | None = None
    if retriever is not None and (knowledge_point or query):
        chunks = retriever.retrieve(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            query=query or knowledge_point,
        )
        if chunks:
            rag_context = "\n".join(f"- {c.content}" for c in chunks)
    persona_hint = get_subject_persona(subject).render()
    return rag_context, persona_hint


# 学科别名 → 标准学科名（自由文本容错）
_SUBJECT_ALIASES = {
    "数学": "数学", "语文": "语文", "英语": "英语", "英文": "英语",
    "科学": "科学", "物理": "物理", "化学": "化学", "生物": "生物",
    "历史": "历史", "地理": "地理", "政治": "政治", "道法": "政治",
    "美术": "美术", "音乐": "音乐", "体育": "体育", "信息": "信息",
}
_QTYPE_MAP = {
    "选择": "choice", "单选": "choice", "选择题": "choice", "多选": "choice",
    "填空": "fill", "填空题": "fill", "判断": "choice", "判断题": "choice",
    "计算": "calc", "计算题": "calc", "应用题": "calc",
    "问答": "open", "解答": "open", "简答题": "open", "问答题": "open",
}
_CN_NUM = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def parse_specs_from_text(text: str) -> list[dict]:
    """从自由文本解析出题规格（悬浮助手一句话出题）。

    识别：科目（标准名/别名）、年级（数字/中文+年级）、数量（N道/题）、题型。
    识别不到时返回空列表（runtime 提示用户补充）。数量上限 5 防滥用。
    """
    import re

    specs: list[dict] = []

    subject = ""
    for alias, std in _SUBJECT_ALIASES.items():
        if alias in text:
            subject = std
            break
    if not subject:
        for s in SUBJECTS:
            if s in text:
                subject = s
                break

    grade = 0
    m = re.search(r"(\d)\s*年级", text)
    if m:
        grade = int(m.group(1))
    else:
        m = re.search(r"([一二三四五六七八九])\s*年级", text)
        if m:
            grade = _CN_NUM.get(m.group(1), 0)

    count = 1
    m = re.search(r"(\d+)\s*(道|题|个)", text)
    if m:
        count = min(int(m.group(1)), 5)
    else:
        m = re.search(r"([一二三四五])\s*(道|题)", text)
        if m:
            count = min(_CN_NUM.get(m.group(1), 1), 5)

    qtype = "choice"
    for kw, qt in _QTYPE_MAP.items():
        if kw in text:
            qtype = qt
            break

    kp = ""
    m = re.search(r"关于\s*《?\s*([\u4e00-\u9fa5A-Za-z0-9]+)", text)
    if m:
        kp = m.group(1)
    else:
        qt_kw = next((kw for kw, _ in _QTYPE_MAP.items() if kw in text), None)
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
                "count": count,
            }
        )
    return specs


def with_skills(persona_hint: str, skills: str) -> str:
    """把业务 SOP（ADR-0030：manifest 声明的 skills/*.md 全文）拼到学科 Persona 之后。"""
    sop = (skills or "").strip()
    return f"{persona_hint}\n\n{sop}" if sop else persona_hint


class QuestionSubAgent(BaseSubAgent):
    business = "question"

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        """出题入口：结构化规格（ctx.extra["specs"]）优先；无则回落自由文本解析。

        结构化路径取代「自由文本 → parse_specs_from_text 正则」的有损往返：规格直接
        进入逐题 prompt 构造，绝不过自然语言（ADR-0034 Phase 1）。
        """
        structured = ctx.extra.get("specs")
        if structured:
            items = build_prompt_from_specs(structured)
        else:
            specs = parse_specs_from_text(message)
            if not specs:
                yield self._finish(
                    "请告诉我科目、年级和题型，例如：「帮我出 3 道三年级分数选择题」。"
                )
                return
            items = expand_specs(specs)

        if not items:
            yield self._finish("未解析到有效的出题规格，请检查科目、年级与题型。")
            return
        tc = self._tool(
            "generate_question",
            label="出题",
            args={"subject": items[0]["subject"], "count": len(items)},
        )
        yield tc.call

        # WF-4 兴趣题模式：focus_interest 是主题列表，按题序轮转分配（与旧 flow 行为一致）。
        focuses = ctx.extra.get("focus_interest") or []
        n_focus = len(focuses)

        generated: list[dict] = []
        for idx, item in enumerate(items):
            focus = focuses[idx % n_focus] if n_focus else None
            rag_context, persona_hint = build_question_context(
                subject=item["subject"],
                grade=item["grade"],
                knowledge_point=item["knowledge_point"],
                query=focus or item["knowledge_point"],
                retriever=self.retriever,
            )
            persona_hint = with_skills(persona_hint, ctx.skills)
            system_prompt, user_prompt, spec = build_question_prompts(
                subject=item["subject"],
                grade=item["grade"],
                knowledge_point=item["knowledge_point"],
                qtype=item["qtype"],
                difficulty=item["difficulty"],
                focus_interest=focus,
                rag_context=rag_context,
                persona_hint=persona_hint,
                history=ctx.history,
            )
            yield step(
                step_label(
                    item["subject"], item["grade"], item["knowledge_point"], item["qtype"]
                )
            )
            async for frame in translate_stream(
                stream_question(
                    self.provider,
                    system_prompt=system_prompt,
                    user_prompt=user_prompt,
                    spec=spec,
                    history=ctx.history,
                )
            ):
                data = frame.data
                if data is not None and data.get("type") == "question":
                    generated.append(data["result"])
                yield frame

        yield tc.result({"count": len(generated)})
        if generated:
            subj = items[0]["subject"]
            yield self._finish(
                f"已生成 {len(generated)} 道{subj}题，题卡中包含题目、选项与解析，"
                f"可据此布置给孩子（保存为任务为后续能力）。"
            )
        else:
            yield self._finish("本次未能生成题目，请调整科目或年级后重试。")
