"""Repository layer for the assistant (悬浮助手) feature.

多轮会话复用与历史读取（ADR-0026）：前端只需带 ``session_id``，后端按 id 取回
``Conversation`` 并载入历史消息拼入 prompt，维持多轮上下文。
"""
from __future__ import annotations

from uuid import UUID

from sqlmodel import Session, func, select

from app.db.models import Conversation, Message


def get_conversation_by_id(session: Session, conv_id: UUID) -> Conversation | None:
    """按主键取回会话；不存在返回 None（调用方负责判归属）。"""
    return session.get(Conversation, conv_id)


def next_turn(session: Session, conv_id: UUID) -> int:
    """该会话已有的消息条数，作为下一帧落库的 turn 序号。"""
    return session.exec(
        select(func.count(Message.id)).where(Message.conversation_id == conv_id)
    ).one()


def load_chat_history(session: Session, conv_id: UUID, *, limit: int = 20) -> list[dict]:
    """读取会话历史（user 输入 + assistant 输出），供多轮上下文拼入 prompt。

    只取 ``role in (user, assistant)`` 且 ``step in (input, output)`` 的可见轮次，
    按 turn 升序；返回 ``[{"role": "user"|"assistant", "content": str}, ...]``，
    最多保留最近 ``limit`` 条，避免历史过长撑爆 prompt。
    """
    rows = session.exec(
        select(Message)
        .where(
            Message.conversation_id == conv_id,
            Message.role.in_(["user", "assistant"]),
            Message.step.in_(["input", "output"]),
        )
        .order_by(Message.turn.asc())
    ).all()
    history = [{"role": m.role, "content": m.content or ""} for m in rows]
    return history[-limit:]


__all__ = [
    "get_conversation_by_id",
    "next_turn",
    "load_chat_history",
]
