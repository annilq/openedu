"""Pydantic schemas for the tutor (AI governance) feature."""

from datetime import date
from uuid import UUID

from sqlmodel import Field, SQLModel


class TutorAskReq(SQLModel):
    subject: str = Field(max_length=32)
    grade: int
    knowledge_point: str = Field(default="", max_length=128)
    context: str | None = None
    question: str = Field(min_length=1, max_length=2000)
    # 可选模型引用：内置 id / ModelConfig id；缺省走家长默认或全局 DEFAULT_MODEL
    model: str | None = None


class TutorAnswer(SQLModel):
    answer: str
    blocked: bool = False
    reason: str | None = None


class TutorLogResp(SQLModel):
    """单条 AI 答疑日志（家长端查看，F-305）。"""

    id: UUID
    grade: int
    subject: str
    knowledge_point: str
    question: str
    answer: str
    input_safe: bool
    output_safe: bool
    blocked: bool
    created_at: object  # datetime | None


class TutorQuotaUpdate(SQLModel):
    """家长设置管控的请求体；字段缺省（None）= 清除该项限制（恢复默认）。"""

    daily_ask_limit: int | None = None
    daily_minutes_limit: int | None = None
    allowed_subjects: list[str] | None = None


class TutorQuotaResp(SQLModel):
    child_id: UUID
    daily_ask_limit: int | None = None
    daily_minutes_limit: int | None = None
    allowed_subjects: list[str] | None = None


class TutorUsageResp(SQLModel):
    """当日用量（家长端展示）；同时回带生效的限额，便于前端直接展示剩余。"""

    child_id: UUID
    date: date
    asks_today: int
    used_seconds: int
    ask_limit: int | None = None
    minutes_limit: int | None = None
    allowed_subjects: list[str] | None = None
