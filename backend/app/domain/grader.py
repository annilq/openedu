import re

from pydantic import BaseModel

from app.core.async_bridge import run_async
from app.domain.provider import EducationLLMProvider


class GradeSchema(BaseModel):
    """开放题批改的线上契约（``output_schema`` 约束解码）。

    属**批改**而非出题：放置于批改领域（原寄居在 ``app.ai.generation`` 出题模块，
    ADR-0032 Q3 归位）。
    """

    correct: bool
    score: float
    explanation: str


class Grader:
    """批改领域服务。客观题归一化比对；开放题委托 provider。"""

    def __init__(self, provider: EducationLLMProvider) -> None:
        self.provider = provider

    @staticmethod
    def _normalize(text: str | None) -> str:
        return re.sub(r"\s+", "", (text or "").strip().lower())

    def grade(self, *, question, student_answer) -> dict:
        if question.qtype == "open":
            return run_async(
                self.provider.grade_open(
                    question=question, student_answer=student_answer
                )
            )
        correct = self._normalize(student_answer) == self._normalize(question.answer)
        return {
            "correct": correct,
            "score": 1.0 if correct else 0.0,
            "explanation": question.explanation or "",
        }
