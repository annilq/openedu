"""出题 SubAgent（ADR-0024 / 文件夹化）：RAG + 学科 Persona 注入。

位于 ``app/ai/subagents/question/``，与本文件夹 ``manifest.py`` 一同被 AgentRuntime
发现并加载。统一契约：``run(message, ctx)`` 异步产出 AG-UI 事件帧（TOOL_CALL / STEP /
THINKING / DATA / TOOL_RESULT / ASSISTANT_MESSAGE），由 runtime 负责
USER_MESSAGE / 路由 THINKING / DONE 与持久化。

出题走**单调用流式**：每题先发 STEP 进度锚点，再把模型推理逐 token 转为 THINKING
增量，JSON 解析 + 安全闸门通过后发 DATA 题卡（ADR-0017 升级）。

出题逻辑（expand_specs / build_question_context）沿用 ADR-0021，零破坏；
新增自由文本解析 ``parse_specs_from_text`` 支撑「悬浮助手一句话出题」。
"""
from __future__ import annotations

from app.ai.generation import build_question_prompts, step_label
from app.ai.runtime.protocol import step
from app.ai.runtime.translate import translate_stream
from app.ai.subagents.base import BaseSubAgent, SubAgentContext
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
    specs: list[dict] = []

    # 科目
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

    # 年级：数字+年级 / 中文+年级
    grade = 0
    import re

    m = re.search(r"(\d)\s*年级", text)
    if m:
        grade = int(m.group(1))
    else:
        m = re.search(r"([一二三四五六七八九])\s*年级", text)
        if m:
            grade = _CN_NUM.get(m.group(1), 0)

    # 数量
    count = 1
    m = re.search(r"(\d+)\s*(道|题|个)", text)
    if m:
        count = min(int(m.group(1)), 5)
    else:
        m = re.search(r"([一二三四五])\s*(道|题)", text)
        if m:
            count = min(_CN_NUM.get(m.group(1), 1), 5)

    # 题型
    qtype = "choice"
    for kw, qt in _QTYPE_MAP.items():
        if kw in text:
            qtype = qt
            break

    # 知识点：尽力抽取，否则留空交给 RAG/Persona
    # 1) 关于《X》/ 关于X（后接 的 / 》 / ， 等分隔符）——允许《》包裹
    kp = ""
    m = re.search(r"关于\s*《?\s*([\u4e00-\u9fa5A-Za-z0-9]+)", text)
    if m:
        kp = m.group(1)
    else:
        # 2) subject 与 题型关键词之间的中文串即知识点（如「数学分数选择题」→ 分数）
        qt_kw = next((kw for kw, _ in _QTYPE_MAP.items() if kw in text), None)
        if subject and qt_kw:
            between = text.split(subject, 1)[-1].split(qt_kw, 1)[0]
            candidate = re.sub(r"[关于的\s]+", "", between)
            # 去掉可能混入的年级描述（如「三年级」）避免污染知识点
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
    """把业务 SOP（ADR-0030：manifest 声明的 skills/*.md 全文）拼到学科 Persona 之后。

    SOP 与 Persona 同为 prompt 提示段，合并后交由 provider 注入。
    """
    sop = (skills or "").strip()
    return f"{persona_hint}\n\n{sop}" if sop else persona_hint


class QuestionSubAgent(BaseSubAgent):
    business = "question"

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        """悬浮助手入口：自由文本 → 逐题（STEP 进度 + THINKING 推理 + DATA 题卡）。"""
        specs = parse_specs_from_text(message)
        if not specs:
            yield self._finish(
                "请告诉我科目、年级和题型，例如：「帮我出 3 道三年级分数选择题」。"
            )
            return

        items = expand_specs(specs)
        tc = self._tool(
            "generate_question",
            label="出题",
            args={"subject": items[0]["subject"], "count": len(items)},
        )
        yield tc.call

        # WF-4 兴趣题模式：focus_interest 是主题列表，按题序轮转分配到单题（与旧 flow 行为一致）。
        focuses = ctx.focus_interest or []
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
            # ADR-0030：SOP（question_sop.md）随 Persona 一起进 prompt
            persona_hint = with_skills(persona_hint, ctx.skills)
            # ADR-0030 收口 #4：prompt 组装在此完成，provider 只收「已组装 prompt + spec」
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
            # STEP：先给进度锚点（前端据此展开该内联区，消除静默等待）
            yield step(
                step_label(
                    item["subject"], item["grade"], item["knowledge_point"], item["qtype"]
                )
            )
            # 流式：语义事件经 Translate 层转帧（推理增量聚合 → 题卡 → 失败明示）。
            async for frame in translate_stream(
                self.provider.generate_question_stream(
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
