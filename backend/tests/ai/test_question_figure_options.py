"""出题侧图形身份键：output_schema / 解析 / prompt 注入（ADR-0089 ticket 02）。

钉住三件事：

1. `QuestionSchema.options` 是**选项对象**（text + figure_key），模型只给键；
2. 解析器把模型产出收成 ``{text, figure_key}``（不猜、不补顶点）；
3. prompt 注入「可用图形清单」时**只给 key + 中文名**——**顶点绝不进 prompt**
   （防模型编坐标）；无清单时不注入该段，行为与从前一致。
"""
from __future__ import annotations

from app.ai.subagents.question.parsers import (
    QuestionOptionOut,
    QuestionSpec,
    assemble_question,
)
from app.ai.subagents.question.pipeline import build_question_prompts


def _spec() -> QuestionSpec:
    return QuestionSpec(
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        qtype="choice",
        difficulty="medium",
    )


def test_output_schema_carries_figure_key_not_vertices():
    """output_schema 的选项只有 text + figure_key，**没有** points/edges 字段。"""
    fields = set(QuestionOptionOut.model_fields)
    assert fields == {"text", "figure_key"}
    assert "points" not in fields and "edges" not in fields


def test_assemble_question_keeps_figure_key():
    out = assemble_question(
        raw={
            "stem": "下列哪些是轴对称图形？",
            "options": [
                {"text": "A. 正方形", "figure_key": "square"},
                {"text": "B. 平行四边形", "figure_key": "para"},
            ],
            "answer": "A. 正方形",
            "explanation": "正方形有四条对称轴。",
        },
        spec=_spec(),
    )
    assert out is not None
    assert [(o["text"], o["figure_key"]) for o in out.options] == [
        ("A. 正方形", "square"),
        ("B. 平行四边形", "para"),
    ]


def test_prompt_injects_catalog_without_vertices():
    _, user_prompt, _ = build_question_prompts(
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        qtype="choice",
        difficulty="medium",
        figure_catalog="square — 正方形\npara — 平行四边形",
    )
    assert "square — 正方形" in user_prompt
    assert "figure_key" in user_prompt
    # 顶点绝不进 prompt（清单里只有 key + 中文名）。
    assert "0." not in user_prompt
    assert "[[" not in user_prompt


def test_prompt_omits_catalog_section_when_absent():
    _, user_prompt, _ = build_question_prompts(
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        qtype="choice",
        difficulty="medium",
    )
    assert "figure_key" not in user_prompt
