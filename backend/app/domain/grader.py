import re

from pydantic import BaseModel

from app.core.async_bridge import run_async
from app.domain.numeric import numeric_equal
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

    @staticmethod
    def _normalize_set(text: str | list[str] | None) -> set[str]:
        """多选题：answer / 作答 均为「｜」连接的选项文本（前端多选取集也按此序列化），

        按集合比对——顺序无关、去重、空白忽略。
        """
        if isinstance(text, list):
            parts = text
        else:
            parts = (text or "").split("|")
        return {Grader._normalize(p) for p in parts if str(p).strip()}

    def grade(self, *, question, student_answer) -> dict:
        if question.qtype == "open":
            return run_async(
                self.provider.grade_open(
                    question=question, student_answer=student_answer
                )
            )
        # 多选题（ADR-0004 D5）：按选项集合比对，顺序/重复不计。
        if getattr(question, "multi", False):
            correct = self._normalize_set(student_answer) == self._normalize_set(
                question.answer
            )
        else:
            correct = self._grade_objective(question, student_answer)
        return {
            "correct": correct,
            "score": 1.0 if correct else 0.0,
            "explanation": question.explanation or "",
        }

    @staticmethod
    def _grade_objective(question, student_answer) -> bool:
        """非 open / 非 multi 的客观题判定。

        数学填空/计算题走数值等价（ADR-0071）：双侧解析成功且量纲兼容、容差内
        相等即正确；**任一端解析失败**（非数值文本）回退现有归一化严格相等——
        安全绳保证「不会比现在更差」（解析歧义收敛到旧行为）。
        """
        if getattr(question, "subject", None) == "数学" and question.qtype in (
            "fill",
            "calc",
        ):
            if numeric_equal(question.answer, student_answer):
                return True
        return Grader._normalize(student_answer) == Grader._normalize(question.answer)
