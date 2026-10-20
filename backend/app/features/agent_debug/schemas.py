"""Pydantic read schemas for the AI observability (debug) feature."""

import uuid
from datetime import datetime

from pydantic import BaseModel, Field
from sqlmodel import SQLModel


class ConversationResp(SQLModel):
    """调试库只读：一条 AI 运行概要。"""

    id: uuid.UUID
    kind: str
    teacher_id: uuid.UUID
    student_id: uuid.UUID | None = None
    model: str | None = None
    title: str | None = None
    ref_task_id: uuid.UUID | None = None
    status: str
    created_at: datetime | None = None
    updated_at: datetime | None = None


class MessageResp(SQLModel):
    """调试库只读：运行内一步。"""

    id: uuid.UUID
    conversation_id: uuid.UUID
    turn: int
    role: str
    step: str
    content: str
    payload: dict | None = None
    model: str | None = None
    input_safe: bool
    output_safe: bool
    blocked: bool
    block_reason: str | None = None
    latency_ms: int | None = None
    usage: dict | None = None
    created_at: datetime | None = None
    # 脱敏标记（ADR-0088 ticket 03）：True = 正文/tool 载荷已被掩码，原文不在响应里。
    # 默认 True（安全默认）：任何不经破窗构造的 MessageResp 都按脱敏处理。
    redacted: bool = True


class ConversationDetailResp(SQLModel):
    """调试库只读：一次 AI 运行 + 其全部步骤（回放用）。"""

    conversation: ConversationResp
    messages: list[MessageResp] = []


class BreakGlassReason(BaseModel):
    """破窗请求体：管理员查看运行全文必须给出理由（留痕审计）。"""

    reason: str = Field(min_length=1, max_length=512)


class BreakGlassLogResp(SQLModel):
    """破窗访问留痕（审计可读）。"""

    id: uuid.UUID
    actor_id: uuid.UUID
    conversation_id: uuid.UUID
    reason: str
    created_at: datetime | None = None
