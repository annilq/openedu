"""出题的线上契约 + 流式解析器（解析管线第 3 层）。

**契约与解析器同源**：``QuestionSchema`` 既是发给模型的 ``output_schema``（约束解码，
模型必须产出合法 JSON），也是解析器读字段的依据。二者在同一个文件里，改 schema
不可能会忘记改解析——此前 prompt 与解析隔 200 行手写状态机揣摩，正是这种漂移的温床。

**解析层只判定，不猜测**：模型不听话（产出为 None / 安全闸门未过）统一走
``QuestionFailed`` 显式事件，由上层决定重试或提示，解析器不做任何宽容兜底。

``SchemaQuestionParser`` 是同步 push 状态机（``feed`` / ``finish``），无 async、
无引擎依赖，可直接用字符串喂入单测。若日后要换成「增量 JSON 抽取」以在纯文本
模型上拿到逐 token 推理，只需新增一个同协议（``feed``/``finish``）的解析器替换即可。

本模块属**出题业务**（ADR-0032 Q3：原 ``app/ai/parsers/question.py`` 归位到 question
子包）；字段读取工具 ``schema_field`` 与批改共用，故下沉至 ``app.domain.structured``。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from pydantic import BaseModel

from agent_core.adapters.genkit import Segment, SegmentKind
from app.domain.provider import (
    GeneratedQuestion,
    QuestionCard,
    QuestionFailed,
    QuestionStreamEvent,
    ReasoningDelta,
)
from app.domain.safety import check_output
from app.domain.structured import schema_field


def qtype_label(qtype: str) -> str:
    return {
        "calc": "计算题",
        "fill": "填空题",
        "choice": "选择题",
        "open": "应用题",
    }.get(qtype, "题目")


class QuestionOut(BaseModel):
    """装配后的题卡（含推理）。``reasoning`` 仅用于流式预览态展示，不落库。"""

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


class QuestionSchema(BaseModel):
    """发给模型的 ``output_schema``：约束解码，保证产出即合法 JSON。"""

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


@dataclass(frozen=True)
class QuestionSpec:
    """题目的不可变部分（由调用方按 spec 回填，模型只出可变字段）。"""

    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    difficulty: str


def assemble_question(
    *,
    raw: dict,
    spec: QuestionSpec,
    reasoning: str = "",
) -> QuestionOut | None:
    """装配 + 安全闸门（唯一闸门，流式与落库共用，ADR-0023）。

    题面 ``stem/answer/explanation`` 未过闸门 → 整题作废（返回 None）。
    推理单独过闸门 → 不安全时**只丢弃推理**，题卡照发（推理是可选的透明度信息，
    不该因为它的措辞而丢掉一道好题）。
    """
    stem = raw.get("stem") or ""
    options = raw.get("options")
    answer = raw.get("answer") or ""
    explanation = raw.get("explanation") or ""
    if not check_output(f"{stem} {answer} {explanation}").safe:
        return None
    text = reasoning or (raw.get("reasoning") or "")
    if text and not check_output(text).safe:
        text = ""
    return QuestionOut(
        subject=spec.subject,
        grade=spec.grade,
        knowledge_point=spec.knowledge_point,
        qtype=spec.qtype,
        difficulty=spec.difficulty,
        stem=stem,
        options=options,
        answer=answer,
        explanation=explanation,
        reasoning=text,
    )


class QuestionStreamParser(Protocol):
    """解析器协议：新增解析策略（如增量 JSON 抽取）实现同一协议即可替换。"""

    def feed(self, seg: Segment) -> list[QuestionStreamEvent]: ...

    def finish(self, output: object) -> list[QuestionStreamEvent]: ...


class SchemaQuestionParser:
    """``output_schema`` 约束下的出题解析器。

    - ``REASONING`` 通道（原生思维链）：逐段直发 ``ReasoningDelta``，零解析。
    - ``TEXT`` 通道：是约束解码产出的 JSON，**不参与增量解析**，只累积到
      ``finish`` 时由 ``resp.output`` 的类型化对象一次性判定。

    模型无原生思维链时（如 deepseek-v4-flash），推理只在 ``finish`` 时随题卡
    整块到达——这是该路线的已知代价，换取的是「解析器零猜测」。
    """

    def __init__(self, *, spec: QuestionSpec) -> None:
        self._spec = spec
        self._reasoning: list[str] = []

    def feed(self, seg: Segment) -> list[QuestionStreamEvent]:
        if seg.kind is SegmentKind.REASONING:
            self._reasoning.append(seg.text)
            return [ReasoningDelta(delta=seg.text)]
        return []

    def finish(self, output: object) -> list[QuestionStreamEvent]:
        if output is None:
            return [QuestionFailed(reason="模型未返回结构化题卡")]
        raw = {
            "stem": schema_field(output, "stem") or "",
            "options": schema_field(output, "options"),
            "answer": schema_field(output, "answer") or "",
            "explanation": schema_field(output, "explanation") or "",
            "reasoning": schema_field(output, "reasoning") or "",
        }
        out = assemble_question(
            raw=raw, spec=self._spec, reasoning="".join(self._reasoning).strip()
        )
        if out is None:
            return [QuestionFailed(reason="生成内容未通过安全校验")]
        return [
            QuestionCard(
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
                ),
                reasoning=out.reasoning,
            )
        ]
