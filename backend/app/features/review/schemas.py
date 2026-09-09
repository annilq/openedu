"""Pydantic schemas for the review feature."""

import uuid
from datetime import datetime

from sqlmodel import SQLModel


class ReviewAnswerSubmit(SQLModel):
    wrong_question_id: uuid.UUID
    student_answer: str


class ReviewItemResp(SQLModel):
    """到期复习项（娃娃端）：含题干、不含答案，附调度进度。"""

    wrong_question_id: uuid.UUID
    question_id: uuid.UUID
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = None
    explanation: str = ""
    wrong_count: int
    review_stage: int
    next_interval_days: int
    due_at: datetime | None = None
