"""工具 ``generate_questions``：按规格流式出题（ADR-0097，原 question.run 主体）。

**流式 tool**（``stream_handler``）：执行期间逐帧 yield STEP / THINKING / DATA，
末帧 ``ToolOutcome`` 带「应出 / 实出 / 失败」计数回灌——收尾话术由 tool loop
第二轮的模型据实生成（本模块**不**产出 ASSISTANT_MESSAGE，那是 loop 收尾轮的
职责）。

规格来源（优先级见 ``specs.specs_from_context``）：``ctx.extra["specs"]``
（ADR-0095 slot filling 结构化规格）→ 模型 args → 课件上下文回填 / message
正则兜底。结构化规格优先——规格已由系统备好时不让模型改写。

provider / retriever 经**闭包**注入（``make_spec``），不落全局状态：装配期
（agent 实例化）写一次，运行期只读。
"""
from __future__ import annotations

from typing import Any, AsyncIterator

from agent_core.protocol import EVENT_STEP, step
from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolOutcome, ToolSpec
from app.ai.subagents.question.pipeline import (
    build_question_prompts,
    step_label,
    stream_question,
)
from app.ai.subagents.question.specs import (
    build_question_context,
    specs_from_context,
    subject_summary,
    with_skills,
)
from app.ai.subagents.question.translate import translate_stream
from app.domain.spec_keywords import SUBJECT_ALIASES

NAME = "generate_questions"
DESCRIPTION = (
    "按科目、年级、题型与数量流式生成题目（题卡含选项与解析）。"
    "用于「出几道题」「来份练习」「出道判断题」等出题意图。"
    "生成期间会逐题推送进度与题卡；只需给出规格，不要自行编造题目内容。"
)

_MAX_COUNT = 5


def _spec_from_args(args: dict[str, Any]) -> dict[str, Any] | None:
    """模型经 args 传来的规格 → spec dict；无科目视为未提供。"""
    subject = str(args.get("subject") or "").strip()
    if not subject:
        return None
    # 别名归一（模型可能填「数学题」这类带后缀写法）
    for alias, std in SUBJECT_ALIASES.items():
        if alias in subject:
            subject = std
            break
    return {
        "subject": subject,
        "grade": int(args.get("grade") or 0),
        "knowledge_point": str(args.get("knowledge_point") or "").strip(),
        "qtype": str(args.get("qtype") or "choice").strip() or "choice",
        "difficulty": str(args.get("difficulty") or "medium").strip() or "medium",
        "semester": str(args.get("semester") or "").strip(),
        "count": max(1, min(int(args.get("count") or 1), _MAX_COUNT)),
        "multi": bool(args.get("multi")),
        "judge": bool(args.get("judge")),
    }


def make_stream_handler(*, provider, retriever=None):
    """构造流式 handler：provider / retriever 闭包注入（装配期一次）。"""

    async def stream_handler(
        args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None
    ) -> AsyncIterator[Any]:
        extra = ctx.extra or {}
        # 规格三级来源：系统备好的 specs（含 slot filling）→ 模型 args → message 正则 /
        # 课件回填。args 规格拼在 specs 之后解析，保证结构化规格优先。
        specs = list(extra.get("specs") or [])
        from_args = _spec_from_args(args)
        if from_args:
            specs.append(from_args)
        items = specs_from_context(specs, ctx=ctx)
        if not items:
            # 无规格可解析：不产出 ASSISTANT_MESSAGE（流式契约），把「缺什么」回灌给
            # 模型，由它在收尾轮据实转问用户。
            yield ToolOutcome(
                {
                    "error": "未解析到出题规格（缺少科目）",
                    "count": 0,
                    "requested": 0,
                    "failed": 0,
                    "fail_reason": "缺少科目：请询问用户要出哪个科目、几年级、什么题型",
                }
            )
            return

        # 反馈边（ADR-0060 D4）：掌握度看板下发的代表错题样例，注入每题 prompt。
        weak_examples = extra.get("weak_examples")

        generated: list[dict] = []
        # 单题失败原因（按题序）：引擎未配置 / 解析或安全闸门未过。逐题串行出题时
        # 「某一题失败」必须留痕——否则多学科出题会静默少题（教师只看到少了某一科，
        # 却没有任何提示）。
        failures: list[str] = []
        # 资料溯源（ADR-0055 §13）：逐题快照 + 去重后的「参考了 N 份资料」计数。
        referenced: set[str] = set()
        for item in items:
            rag_context, persona_hint, item_refs = build_question_context(
                subject=item["subject"],
                grade=item["grade"],
                knowledge_point=item["knowledge_point"],
                query=item["knowledge_point"],
                retriever=retriever,
            )
            referenced.update(ref["material"] for ref in item_refs)
            persona_hint = with_skills(persona_hint, ctx.skills)
            system_prompt, user_prompt, spec = build_question_prompts(
                subject=item["subject"],
                grade=item["grade"],
                knowledge_point=item["knowledge_point"],
                qtype=item["qtype"],
                difficulty=item["difficulty"],
                semester=item.get("semester", ""),
                rag_context=rag_context,
                persona_hint=persona_hint,
                history=ctx.history,
                weak_examples=weak_examples,
                multi=item.get("multi", False),
                # 判断题（ADR-0072 闭环）：题面强制「陈述句 + 对/错两个选项」。
                judge=item.get("judge", False),
                # 图形化选项（ADR-0089）：注入可用图形清单，模型只填身份键。
                figure_catalog=_figure_catalog(
                    session,
                    teacher_id=extra.get("teacher_id"),
                    subject=item["subject"],
                    grade=item["grade"],
                    knowledge_point=item["knowledge_point"],
                    semester=item.get("semester", ""),
                ),
            )
            # STEP 进度锚点（原 run() 的 yield step(...)）：前端据此展示「正在出第 N 题」。
            yield step(
                step_label(
                    item["subject"],
                    item["grade"],
                    item["knowledge_point"],
                    item["qtype"],
                )
            )
            async for frame in translate_stream(
                stream_question(
                    provider,
                    system_prompt=system_prompt,
                    user_prompt=user_prompt,
                    spec=spec,
                    history=ctx.history,
                )
            ):
                # 单题失败：translate_stream 把 QuestionFailed 转成 STEP(status="error")。
                # 帧照常下发（前端据此展示失败），同时留痕到 failures 供收尾汇总。
                if frame.eventType == EVENT_STEP and frame.status == "error":
                    failures.append(frame.label or "生成失败")
                    yield frame
                    continue
                data = frame.data
                if data is not None and data.get("type") == "question":
                    # 溯源快照随题卡下发（ADR-0055 §10）；客户端原样回传落库。
                    if item_refs:
                        data["result"]["source_refs"] = item_refs
                    generated.append(data["result"])
                yield frame

        # 回灌计数（不带题卡全文——那会让收尾轮上下文爆炸；话术据计数生成）。
        yield ToolOutcome(
            {
                "count": len(generated),
                "requested": len(items),
                "failed": len(failures),
                "fail_reason": failures[0] if failures else None,
                "referenced_materials": len(referenced),
                "unindexed_materials": extra.get("unindexed_materials") or 0,
                # 多学科概览（空串=单学科）：收尾轮据它列出各科数量，
                # 不得只报第一科（旧实现的错话由这条数据 + system prompt 双点守）。
                "subject_summary": subject_summary(items),
            }
        )

    return stream_handler


def _figure_catalog(session, **kwargs) -> str | None:
    """图形清单（ADR-0089 §4.3）：增强项，任何异常都不阻断出题主链路。"""
    from app.ai.subagents.question.specs import figure_catalog_for_question

    try:
        return figure_catalog_for_question(session, **kwargs)
    except Exception:  # noqa: BLE001 — 目录是增强，绝不阻断出题
        return None


_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "subject": {
            "type": "string",
            "description": (
                "科目；取值须与系统口径一致（如 数学 / 语文 / 英语），不要加「题」等后缀。"
            ),
        },
        "grade": {
            "type": "integer",
            "description": "年级（如 3 表示三年级）；0 或空＝未指定。",
        },
        "qtype": {
            "type": "string",
            "description": "题型：choice 选择 / fill 填空 / calc 计算 / open 解答；空＝选择。",
        },
        "count": {
            "type": "integer",
            "description": f"出题数量（1-{_MAX_COUNT}）；0 或空＝1 道。",
        },
        "knowledge_point": {
            "type": "string",
            "description": "知识点（须与教材原文一致，如「一元二次方程」）；空＝按教材随机。",
        },
        "difficulty": {
            "type": "string",
            "description": "难度：easy / medium / hard；空＝medium。",
        },
        "semester": {
            "type": "string",
            "description": "学期：上 / 下 / 空（不分学期）。",
        },
        "multi": {
            "type": "boolean",
            "description": "是否多选题（仅 choice 题型有意义）。",
        },
        "judge": {
            "type": "boolean",
            "description": "是否判断题（题面为陈述句 + 对/错两个选项）。",
        },
    },
    "required": [],
}


def make_spec(*, provider, retriever=None) -> ToolSpec:
    """装配期构造 SPEC：provider / retriever 闭包进流式 handler。"""
    return ToolSpec(
        name=NAME,
        label="出题",
        description=DESCRIPTION,
        schema=_SCHEMA,
        stream_handler=make_stream_handler(provider=provider, retriever=retriever),
    )
