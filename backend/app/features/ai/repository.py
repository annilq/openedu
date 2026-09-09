"""Repository layer for the AI observability (debug) feature."""

import uuid
from datetime import UTC, datetime

from sqlmodel import Session, func, select

from app.db.models import Conversation, Message


def create_conversation(
    *,
    session: Session,
    kind: str,
    parent_id: uuid.UUID,
    child_id: uuid.UUID | None = None,
    model: str | None = None,
    title: str | None = None,
    ref_task_id: uuid.UUID | None = None,
    status: str = "running",
) -> Conversation:
    conv = Conversation(
        kind=kind,
        parent_id=parent_id,
        child_id=child_id,
        model=model,
        title=title,
        ref_task_id=ref_task_id,
        status=status,
    )
    session.add(conv)
    session.commit()
    session.refresh(conv)
    return conv


def add_message(
    *,
    session: Session,
    conversation_id: uuid.UUID,
    role: str,
    step: str = "output",
    content: str = "",
    payload: dict | None = None,
    model: str | None = None,
    input_safe: bool = True,
    output_safe: bool = True,
    blocked: bool = False,
    block_reason: str | None = None,
    latency_ms: int | None = None,
    usage: dict | None = None,
    turn: int | None = None,
) -> Message:
    if turn is None:
        # 同 conversation 内自增序号（并发下近似即可，仅排序展示用）。
        n = session.exec(
            select(func.count(Message.id)).where(Message.conversation_id == conversation_id)
        ).one()
        turn = n
    msg = Message(
        conversation_id=conversation_id,
        turn=turn,
        role=role,
        step=step,
        content=content,
        payload=payload,
        model=model,
        input_safe=input_safe,
        output_safe=output_safe,
        blocked=blocked,
        block_reason=block_reason,
        latency_ms=latency_ms,
        usage=usage,
    )
    session.add(msg)
    session.commit()
    session.refresh(msg)
    return msg


def finish_conversation(
    *, session: Session, conversation_id: uuid.UUID, status: str = "done"
) -> None:
    conv = session.get(Conversation, conversation_id)
    if conv is not None:
        conv.status = status
        conv.updated_at = datetime.now(UTC)
        session.add(conv)
        session.commit()


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
