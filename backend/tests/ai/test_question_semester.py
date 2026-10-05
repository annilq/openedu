"""学期维度（ADR-0061 发布任务对接资料库）出题链路透传单测。

学期从「发布任务表单」一路流到「每道题落库」，任一环掉链子，讲解时就匹配不到
同学期的知识点交互场景。本文件钉住三个关键接缝：
1. ``expand_specs``：TaskSpec（含学期）按 count 展开为每题一项，学期不丢；
2. ``build_question_prompts``：学期进 ``QuestionSpec``（供装配回填）且进 prompt
   语境（让模型知道按哪个学期的教材口径出题）；
3. ``stream_question``：学期从 spec 经装配回填到 ``GeneratedQuestion``（随题卡下发）。
"""
from __future__ import annotations

import asyncio

from agent_core.ports import StructuredDone
from app.ai.subagents.question.agent import expand_specs
from app.ai.subagents.question.parsers import QuestionSpec
from app.ai.subagents.question.pipeline import build_question_prompts, stream_question
from app.domain.provider import QuestionCard
from tests.ai.test_generate_question_stream import _FakeProvider, _q_dict


# ───────────────────────── 1) 规格展开：学期随每题下发 ─────────────────────────
def test_expand_specs_carries_semester():
    """TaskSpec 展开为每题一项时，学期必须逐项保留（否则后续全丢）。"""
    items = expand_specs(
        [
            {
                "subject": "数学",
                "grade": 4,
                "knowledge_point": "图形的运动（轴对称）",
                "qtype": "choice",
                "difficulty": "medium",
                "semester": "上学期",
                "count": 3,
            }
        ]
    )
    assert len(items) == 3
    assert all(it["semester"] == "上学期" for it in items)


def test_expand_specs_defaults_semester_empty():
    """未指定学期（老数据/ 自由文本）→ 学期为 ''（整学年），不报错。"""
    items = expand_specs(
        [
            {
                "subject": "数学",
                "grade": 3,
                "knowledge_point": "分数",
                "qtype": "choice",
                "count": 1,
            }
        ]
    )
    assert items[0]["semester"] == ""


# ───────────────────────── 2) prompt 组装：学期进 spec + 进语境 ─────────────────────────
def test_build_prompts_puts_semester_in_spec_and_clause():
    _, user_prompt, spec = build_question_prompts(
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        qtype="choice",
        difficulty="medium",
        semester="下学期",
    )
    # spec 携带学期 → 供 assemble_question 回填到题目
    assert isinstance(spec, QuestionSpec)
    assert spec.semester == "下学期"
    # prompt 语境点明学期（模型据此对齐该学期教材口径）
    assert "下学期" in user_prompt


def test_build_prompts_semester_empty_uses_year_wide_wording():
    _, user_prompt, spec = build_question_prompts(
        subject="数学",
        grade=4,
        knowledge_point="分数",
        qtype="calc",
        difficulty="medium",
        semester="",
    )
    assert spec.semester == ""
    # 未指定学期时说「整学年」而不是留空
    assert "整学年" in user_prompt


# ───────────────────────── 3) 流式出题：学期随题卡下发 ─────────────────────────
def test_stream_question_card_carries_semester():
    """学期从 spec 经装配回填到 GeneratedQuestion（前端据此回传落库）。"""
    spec = QuestionSpec(
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        qtype="choice",
        difficulty="medium",
        semester="上学期",
    )
    provider = _FakeProvider([StructuredDone(data=_q_dict())])

    async def _run():
        return [
            ev
            async for ev in stream_question(
                provider, system_prompt="s", user_prompt="u", spec=spec
            )
        ]

    events = asyncio.run(_run())
    cards = [e for e in events if isinstance(e, QuestionCard)]
    assert len(cards) == 1
    assert cards[0].question.semester == "上学期"
