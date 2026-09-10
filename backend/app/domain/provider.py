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

    @abstractmethod
    async def grade_open(self, *, question, student_answer) -> dict:
        """开放题批改，返回 {"correct": bool, "score": float, "explanation": str}"""
        ...
