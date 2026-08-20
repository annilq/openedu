import asyncio
import re

from app.domain.provider import LLMProvider


class Grader:
    """批改领域服务。客观题归一化比对；开放题委托 provider。"""

    def __init__(self, provider: LLMProvider) -> None:
        self.provider = provider

    @staticmethod
    def _normalize(text: str | None) -> str:
        return re.sub(r"\s+", "", (text or "").strip().lower())

    def grade(self, *, question, student_answer) -> dict:
        if question.qtype == "open":
            return asyncio.run(
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
