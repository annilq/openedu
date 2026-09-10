from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.ai.parsers.question import QuestionSpec


@dataclass
class GeneratedQuestion:
    subject: str
    grade: int
    knowledge_point: str
    qtype: str  # choice | fill | calc | open
    stem: str
    options: list[str] | None
    answer: str
    explanation: str
    difficulty: str


# ─────────────── 出题流式事件（ADR-0017 升级：推理增量 + 成品题卡） ───────────────
# 这是「引擎层」的语义 schema，与传输协议无关：上层（SubAgent）负责把它翻译成
# AG-UI 帧（THINKING / DATA）。加新语义只需加一个类型，不动 SSE 协议。
@dataclass(frozen=True)
class ReasoningDelta:
    """出题推理的文本增量（token 级）。

    两种来源：原生思维链模型（DeepSeek-R1 / o-series）的 reasoning token；
    普通模型按 prompt 约定写在 ``<reasoning>…</reasoning>`` 里的思路文本。
    """

    delta: str


@dataclass(frozen=True)
class QuestionCard:
    """一道成品题卡（已过安全闸门）。``reasoning`` 为本题完整推理，随卡下发。"""

    question: GeneratedQuestion
    reasoning: str = ""


@dataclass(frozen=True)
class QuestionFailed:
    """单题生成失败：解析失败 / 安全闸门未过 / 模型未返回结构化产出。

    失败**显式成事件**，不再静默跳过——上层（SubAgent）翻译成 status=error 的
    STEP 帧，前端可见「这题为什么没出来」。容错不放在解析层猜，交给调用方重试。
    """

    reason: str


QuestionStreamEvent = ReasoningDelta | QuestionCard | QuestionFailed


class LLMProvider(ABC):
    """出题/批改引擎的统一抽象。业务只依赖此接口，不感知具体厂商。"""

    @abstractmethod
    async def generate_question(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        spec: "QuestionSpec",
        history: list[dict] | None = None,  # 多轮对话历史（ADR-0026 服务端会话）
    ) -> GeneratedQuestion | None:
        """非流式出题：prompt 已由调用方组装好，provider 只负责调用模型并产出题卡。

        ADR-0030 收口 #4：接口不再泄漏 9 个业务 kwarg（subject/grade/qtype/...），
        「换 provider 不用懂教育」——新增题型/字段只需改 spec + 组装方，不动本接口。
        ``spec`` 为题目不可变身份，由调用方给出、回填模型产出（模型不一定回写）。
        模型产不安全时返回 None，由上层降级。
        """
        ...

    async def generate_question_stream(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        spec: "QuestionSpec",
        history: list[dict] | None = None,
    ) -> AsyncIterator[QuestionStreamEvent]:
        """出题流式：逐段产出推理增量与成品题卡。

        默认实现退化为「一次性生成 → 单张题卡」（无推理增量），保证不支持流式的
        实现也能接上同一条调用链；``GenkitProvider`` 覆写为真正的逐 token 流式。

        ADR-0030 收口 #4：与 ``generate_question`` 一致，只收已组装 prompt + spec。
        """
        q = await self.generate_question(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            spec=spec,
            history=history,
        )
        if q is not None:
            yield QuestionCard(question=q)

    @abstractmethod
    async def grade_open(self, *, question, student_answer) -> dict:
        """开放题批改，返回 {"correct": bool, "score": float, "explanation": str}"""
        ...

    @abstractmethod
    async def tutor(
        self, *, grade, subject, knowledge_point, context, question,
        history: list[dict] | None = None,
    ) -> str:
        """AI 伴学答疑（F-302）：针对娃娃的提问返回适龄、纯学习相关的讲解文本。

        实现应自行注入「仅适合对应年级、纯学习相关」的系统约束（见 domain/safety）。
        ``history`` 为多轮对话历史（ADR-0026 服务端会话），实现应拼入上下文以衔接前轮。
        """
        ...
