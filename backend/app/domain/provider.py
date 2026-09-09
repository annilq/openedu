from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass


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
        subject,
        grade,
        knowledge_point,
        qtype,
        difficulty,
        interests: list[str] | None = None,  # 轻融入：娃娃兴趣池（受控分类叶子 key）
        focus_interest: str | None = None,  # 兴趣题模式：聚焦的单个兴趣主题
        rag_context: str | None = None,  # ADR-0021：知识库检索命中内容（对齐教材口径）
        persona_hint: str | None = None,  # ADR-0021：学科 Persona 渲染文本（语气/适龄/约定）
        history: list[dict] | None = None,  # 多轮对话历史（ADR-0026 服务端会话）
    ) -> GeneratedQuestion: ...

    async def generate_question_stream(
        self,
        *,
        subject,
        grade,
        knowledge_point,
        qtype,
        difficulty,
        interests: list[str] | None = None,
        focus_interest: str | None = None,
        rag_context: str | None = None,
        persona_hint: str | None = None,
        history: list[dict] | None = None,
    ) -> AsyncIterator[QuestionStreamEvent]:
        """出题流式：逐段产出推理增量与成品题卡。

        默认实现退化为「一次性生成 → 单张题卡」（无推理增量），保证不支持流式的
        实现也能接上同一条调用链；``GenkitProvider`` 覆写为真正的逐 token 流式。
        """
        q = await self.generate_question(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            qtype=qtype,
            difficulty=difficulty,
            interests=interests,
            focus_interest=focus_interest,
            rag_context=rag_context,
            persona_hint=persona_hint,
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
