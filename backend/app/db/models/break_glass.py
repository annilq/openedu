"""破窗访问留痕（ADR-0088 ticket 03）。

管理员显式查看某次 AI 运行全文（含脱敏的 tool 参数/结果）时写一条审计记录：
谁、何时、读了哪段对话全文、理由。原文始终留在业务 DB，不外流到独立观测后端。
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc


class BreakGlassAccess(SQLModel, table=True):
    """一次破窗访问（管理员查看运行全文）的审计留痕。"""

    __tablename__ = "break_glass_access"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    actor_id: uuid.UUID = Field(index=True)  # 触发破窗的管理员
    conversation_id: uuid.UUID = Field(index=True)  # 被读取全文的运行
    reason: str = Field(max_length=512)
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
