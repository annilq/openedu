import uuid
from datetime import datetime

from sqlalchemy import JSON, DateTime
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc


class Question(SQLModel, table=True):
    """题库层（ADR-0004 D2）：Question 表本身即题库，删 task_id 独立实体，可跨 Task 复用。

    parent_id（题库复用闭环）：归属家长，实现 owner 隔离，避免多家庭互通题库。
    旧库通过 db.run_migrations 回填（见 backend/app/core/db.py）。
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")  # 题库 owner 隔离（闭环）
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = Field(default=None, sa_type=JSON)
    answer: str | None = None
    explanation: str | None = None
    difficulty: str | None = None
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
