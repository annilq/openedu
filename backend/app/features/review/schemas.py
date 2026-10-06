"""Pydantic schemas for the review feature."""

import uuid
from datetime import datetime

from sqlmodel import SQLModel


class ReviewAnswerSubmit(SQLModel):
    wrong_question_id: uuid.UUID
    student_answer: str


class ReviewItemResp(SQLModel):
    """到期复习项（学生端）：含题干、不含答案，附调度进度。"""

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
    # 是否多选题（ADR-0004 D5）：choice 题且多正确项时 True，前端渲染复选、批改按集合比对。
    multi: bool = False
    # 几何选项组（ADR-0061 §O）：选择题每个选项本身是图形时下发，前端渲染成每个图形
    # 一个可交互场景；无则 None。复用 Question.scene_spec 快照，前端只消费不解释。
    scene_spec: dict | None = None
