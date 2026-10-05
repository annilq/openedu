"""教育域 LLM 抽象（agent_core.ports.LLMProvider 的教育扩展）。

ADR-0031：通用消息级 ``LLMProvider`` 已上移到 ``agent_core.ports``；本文件只保留
**教育专有**的扩展与结构体：

- ``EducationLLMProvider``：在通用 ``LLMProvider`` 之上，追加教育特有的 ``tutor`` /
  ``grade_open``（伴学答疑 / 开放题批改）。业务域服务（TutorService / Grader）依赖它，
  而非通用接口——通用框架不认识「年级 / 知识点」。
- 出题 / 题卡相关结构体（``GeneratedQuestion`` / ``QuestionStreamEvent`` 等）：教育域语义，
  随 ``app/ai/parsers/question.py`` 与出题 subagent 使用，不进 agent_core。
"""

from __future__ import annotations

from abc import abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import TYPE_CHECKING

from agent_core.ports import LLMProvider

if TYPE_CHECKING:
    pass

__all__ = [
    "LLMProvider",  # 通用接口（re-export，兼容历史 import）
    "EducationLLMProvider",
    "GeneratedQuestion",
    "ReasoningDelta",
    "QuestionCard",
    "QuestionFailed",
    "QuestionStreamEvent",
]


# 兼容 re-export：历史 ``from app.domain.provider import LLMProvider`` 仍指向通用接口
# （已在上方 from import 中引入）。


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
    # 是否多选题（ADR-0004 D5）：choice 题可多选；批改按选项集合比对。
    # 置于无默认值字段之后，避免 dataclass「默认字段前置」顺序错误。
    multi: bool = False
    # 学期维度（ADR-0061 发布任务对接资料库）：'' = 不限/整学年；'上学期' / '下学期'。
    # 随题落库，讲解时按 (parent_id, subject, grade, knowledge_point, semester) 匹配
    # 家长私有知识点模板，进而演示该知识点预设的交互场景。
    semester: str = ""
    # 资料溯源快照（ADR-0055 §10）：[{material, snippet}]；无 RAG 时为 None。
    # 由 SubAgent 在题卡帧上注入（pipeline 不感知检索层）。
    source_refs: list[dict] | None = None


# ─────────────── 出题流式事件（引擎层语义 schema，与传输协议无关） ───────────────
@dataclass(frozen=True)
class ReasoningDelta:
    delta: str


@dataclass(frozen=True)
class QuestionCard:
    question: GeneratedQuestion
    reasoning: str = ""


@dataclass(frozen=True)
class QuestionFailed:
    reason: str


QuestionStreamEvent = ReasoningDelta | QuestionCard | QuestionFailed


class EducationLLMProvider(LLMProvider):
    """教育域 LLM 抽象：通用消息级 ``stream`` + 教育特有的伴学 / 批改。"""

    @abstractmethod
    async def tutor(
        self,
        *,
        grade: int,
        subject: str,
        knowledge_point: str,
        context: str | None,
        question: str,
        history: list[dict] | None = None,
    ) -> str | None:
        """AI 伴学答疑：返回适龄、纯学习相关的讲解文本。"""
        ...

    async def tutor_stream(
        self,
        *,
        grade: int,
        subject: str,
        knowledge_point: str,
        context: str | None,
        question: str,
        history: list[dict] | None = None,
    ) -> AsyncIterator[str]:
        """伴学答疑流式变体：逐文本增量 yield（供 SSE 边生成边下推）。

        默认实现委托 ``tutor()`` 一次性返回（非流式 provider 的兜底，保证
        ``TutorService.aexplain_stream`` 对任意 provider 都可驱动）；真正的逐 token
        流式由 GenkitProvider 重写。
        """
        answer = await self.tutor(
            grade=grade,
            subject=subject,
            knowledge_point=knowledge_point,
            context=context,
            question=question,
            history=history,
        )
        if answer:
            yield answer

    @abstractmethod
    async def grade_open(self, *, question, student_answer) -> dict:
        """开放题批改，返回 {"correct": bool, "score": float, "explanation": str}"""
        ...

    @property
    def configured(self) -> bool:
        """引擎是否可用（子类可覆盖；默认 True，兼容非 genkit 实现）。"""
        return True
