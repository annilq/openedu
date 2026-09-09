import uuid
from datetime import date, datetime

from sqlalchemy import DateTime, UniqueConstraint
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc, get_review_due_utc


class AnswerRecord(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    question_id: uuid.UUID = Field(foreign_key="question.id")
    child_id: uuid.UUID = Field(foreign_key="user.id")
    student_answer: str
    correct: bool = False
    score: float = 0.0
    source: str = Field(max_length=16, default="practice")  # practice|review
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class Checkin(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id")
    task_id: uuid.UUID = Field(foreign_key="task.id")
    checkin_date: date = Field(default_factory=date.today)


class WrongQuestion(SQLModel, table=True):
    """错题集：按 child + question 唯一，重复答错只累加次数，不建多条（故事 13）。

    遗忘曲线调度字段（故事 14/17）：
    - review_stage：当前阶段 0..4，对应间隔 1/2/4/7/15 天
    - last_wrong_at：最近一次答错时间，作为计时器起点（重复答错重置）
    - due_at：下次复习到期时间
    """

    __table_args__ = (UniqueConstraint("child_id", "question_id"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id", index=True)
    question_id: uuid.UUID = Field(foreign_key="question.id")
    first_wrong_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    wrong_count: int = Field(default=1)
    review_stage: int = Field(default=0)
    last_wrong_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    due_at: datetime | None = Field(
        default_factory=get_review_due_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
