import uuid
from datetime import date, datetime

from sqlalchemy import JSON, DateTime, UniqueConstraint
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc, get_usage_date_utc


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


class TutorQuota(SQLModel, table=True):
    """家长按娃配置的 AI 使用管控（每娃一条）。

    - daily_ask_limit：每日提问条数上限；None → 回退全局 TUTOR_DAILY_LIMIT；0 → 今日禁用
    - daily_minutes_limit：每日累计使用分钟上限；None → 不限时；0 → 今日禁用
    - allowed_subjects：允许提问的学科白名单；None → 不限
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id", unique=True, index=True)
    daily_ask_limit: int | None = None
    daily_minutes_limit: int | None = None
    allowed_subjects: list[str] | None = Field(default=None, sa_type=JSON)
    updated_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class TutorUsage(SQLModel, table=True):
    """当日 AI 使用累计（按 child + 日期唯一）。

    次数口径沿用 TutorLog 计数（count_tutor_today）；
    此表只累计服务端实测的答疑耗时秒数，用于时长上限判定。
    """

    __table_args__ = (UniqueConstraint("child_id", "usage_date"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id", index=True)
    usage_date: date = Field(default_factory=get_usage_date_utc)
    used_seconds: int = Field(default=0)
