"""Repository layer for the assistant (悬浮助手) feature.

多轮会话复用与历史读取（ADR-0026）：前端只需带 ``session_id``，后端按 id 取回
``Conversation`` 并载入历史消息拼入 prompt，维持多轮上下文。
"""
from __future__ import annotations

from uuid import UUID

from sqlmodel import Session, func, select

from app.db.models import Conversation, Message

# compaction（P1）护栏：超过则丢弃最旧轮次，避免长推理对话撑爆 prompt。
# 经验保守值，仅做「不溢出」上界；精确计费交给模型方。
CHAT_HISTORY_MAX_TOKENS = 4000
# 单条消息 token 估算开销（角色 / 结构），与内容按 ~4 字符 / token 累加。
_MSG_TOKEN_OVERHEAD = 4


def _estimate_tokens(history: list[dict]) -> int:
    """粗估历史 token 数：内容按 ~4 字符 / token + 单条结构开销。"""
    return sum(len(m.get("content") or "") // 4 + _MSG_TOKEN_OVERHEAD for m in history)


def _compact_history(
    history: list[dict], *, limit: int, max_tokens: int
) -> list[dict]:
    """compaction 纯函数（与 DB 无关，便于单测）。

    1) 硬消息数上限：仅保留最近 ``limit`` 条；
    2) token 预算护栏：从最旧轮次起丢弃，直到不超 ``max_tokens`` 或仅剩 1 条。
    短对话（未触任一上限）保持原顺序与内容不变。
    """
    if len(history) > limit:
        history = history[-limit:]
    while len(history) > 1 and _estimate_tokens(history) > max_tokens:
        history = history[1:]
    return history


def get_conversation_by_id(session: Session, conv_id: UUID) -> Conversation | None:
    """按主键取回会话；不存在返回 None（调用方负责判归属）。"""
    return session.get(Conversation, conv_id)


def next_turn(session: Session, conv_id: UUID) -> int:
    """该会话已有的消息条数，作为下一帧落库的 turn 序号。"""
    return session.exec(
        select(func.count(Message.id)).where(Message.conversation_id == conv_id)
    ).one()


def load_chat_history(
    session: Session,
    conv_id: UUID,
    *,
    limit: int = 20,
    max_tokens: int = CHAT_HISTORY_MAX_TOKENS,
) -> list[dict]:
    """读取会话历史（user 输入 + assistant 输出），供多轮上下文拼入 prompt。

    只取 ``role in (user, assistant)`` 且 ``step in (input, output)`` 的可见轮次，
    按 turn 升序；返回 ``[{"role": "user"|"assistant", "content": str}, ...]``。

    compaction（P1）：经 :func:`_compact_history` 先按消息数、再按 token 预算收敛，
    短对话行为与原来（朴素 ``[:limit]``）一致。
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
    return _compact_history(history, limit=limit, max_tokens=max_tokens)


__all__ = [
    "get_conversation_by_id",
    "next_turn",
    "load_chat_history",
]
