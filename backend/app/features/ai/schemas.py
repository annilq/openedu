"""Pydantic read schemas for the AI observability (debug) feature."""

import uuid
from datetime import datetime

from sqlmodel import SQLModel


class ConversationResp(SQLModel):
    """调试库只读：一条 AI 运行概要。"""

    id: uuid.UUID
    kind: str
    parent_id: uuid.UUID
    child_id: uuid.UUID | None = None
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


class ConversationDetailResp(SQLModel):
    """调试库只读：一次 AI 运行 + 其全部步骤（回放用）。"""

    conversation: ConversationResp
    messages: list[MessageResp] = []
