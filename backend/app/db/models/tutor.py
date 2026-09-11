import uuid
from datetime import datetime

from sqlalchemy import DateTime
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc


class TutorLog(SQLModel, table=True):
    """AI 伴学答疑交互日志（F-305，家长可查）。"""

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id", index=True)
    grade: int
    subject: str = Field(max_length=32)
    knowledge_point: str = Field(default="", max_length=128)
    question: str
    answer: str
    input_safe: bool = True
    output_safe: bool = True
    blocked: bool = False  # 因安全原因返回兜底（未调用/未采用模型输出）
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
