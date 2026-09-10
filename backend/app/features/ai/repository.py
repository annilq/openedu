"""Repository layer for the AI observability (debug) feature.

**只读回放**：家长查看自家 AI 运行（``Conversation`` / ``Message``），供
``/ai/debug/conversations`` 端点消费。

写入侧不在此模块：会话/消息的落库已收敛到 ``app.features.assistant``（ADR-0026 废除
``debug_log``，其写入函数于 ADR-0032 清理为死代码后删除）。
"""

import uuid

from sqlmodel import Session, select

from app.db.models import Conversation, Message


def list_conversations(
    *,
    session: Session,
    parent_id: uuid.UUID,
    child_id: uuid.UUID | None = None,
    kind: str | None = None,
    limit: int = 100,
) -> list[Conversation]:
    """按 owner(parent_id) 查 AI 运行；可再按 child/kind 过滤，时间倒序。"""
    stmt = select(Conversation).where(Conversation.parent_id == parent_id)
    if child_id is not None:
        stmt = stmt.where(Conversation.child_id == child_id)
    if kind is not None:
        stmt = stmt.where(Conversation.kind == kind)
    return list(
        session.exec(stmt.order_by(Conversation.created_at.desc()).limit(limit)).all()
    )


def get_conversation_messages(
    *, session: Session, conversation_id: uuid.UUID
) -> list[Message]:
    """取某运行内全部步骤，按 turn 正序（回放用）。"""
    return list(
        session.exec(
            select(Message)
            .where(Message.conversation_id == conversation_id)
            .order_by(Message.turn)
        ).all()
    )
