"""班级 schemas（ADR-0068）。"""

from datetime import datetime
from uuid import UUID

from sqlmodel import SQLModel


class ClassCreate(SQLModel):
    name: str
    grade: int  # 1–9


class ClassUpdate(SQLModel):
    name: str | None = None
    grade: int | None = None


class ClassResp(SQLModel):
    id: UUID
    name: str
    grade: int
    student_count: int = 0
    created_at: datetime
