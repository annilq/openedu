from abc import ABC, abstractmethod
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


class LLMProvider(ABC):
    """出题/批改引擎的统一抽象。业务只依赖此接口，不感知具体厂商。"""

    @abstractmethod
    async def generate_question(
        self, *, subject, grade, knowledge_point, qtype, difficulty
    ) -> GeneratedQuestion: ...

    @abstractmethod
    async def grade_open(self, *, question, student_answer) -> dict:
        """开放题批改，返回 {"correct": bool, "score": float, "explanation": str}"""
        ...
