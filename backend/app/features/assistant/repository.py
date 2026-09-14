"""Repository layer for the assistant (悬浮助手) feature.

多轮会话复用与历史读取（ADR-0026）：前端只需带 ``session_id``，后端按 id 取回
``Conversation`` 并载入历史消息拼入 prompt，维持多轮上下文。
"""
from __future__ import annotations

from collections.abc import Awaitable, Callable
from uuid import UUID

from sqlmodel import Session, func, select

from app.db.models import Conversation, Message

# compaction（P1/P2）护栏：超过则丢弃最旧轮次，避免长推理对话撑爆 prompt。
# 经验保守值，仅做「不溢出」上界；精确计费交给模型方。
CHAT_HISTORY_MAX_TOKENS = 4000
# 单条消息 token 估算开销（角色 / 结构），与内容按 ~4 字符 / token 累加。
_MSG_TOKEN_OVERHEAD = 4
# 自动摘要（P2）注入前缀：history 下游约定 role 仅 user/assistant（ports.py），
# 故摘要以 user 角色 + 前缀注入，不破坏 {role, content} 形状，且能被所有 provider 消费。
SUMMARY_PREFIX = "[历史摘要]"


def _estimate_tokens(history: list[dict]) -> int:
    """粗估历史 token 数：内容按 ~4 字符 / token + 单条结构开销。"""
    return sum(len(m.get("content") or "") // 4 + _MSG_TOKEN_OVERHEAD for m in history)


def _read_history(session: Session, conv_id: UUID) -> list[dict]:
    """读取会话原始历史（user 输入 + assistant 输出）为 [{role, content}]。"""
    rows = session.exec(
        select(Message)
        .where(
            Message.conversation_id == conv_id,
            Message.role.in_(["user", "assistant"]),
            Message.step.in_(["input", "output"]),
        )
        .order_by(Message.turn.asc())
    ).all()
    return [{"role": m.role, "content": m.content or ""} for m in rows]


def _split_compaction(
    history: list[dict], *, limit: int, max_tokens: int
) -> tuple[list[dict], list[dict]]:
    """返回 ``(dropped, kept)``：先按条数截最近 N 条，再按 token 预算从最旧丢弃。

    ``dropped`` 保持最旧→较旧的时间顺序，便于交给 summarizer 生成连贯摘要；
    ``kept`` 为留在上下文的最近轮次（最新一条始终保留，见 ``_compact_history`` 的兜底）。
    """
    dropped: list[dict] = []
    if len(history) > limit:
        dropped = history[:-limit]
        history = history[-limit:]
    while len(history) > 1 and _estimate_tokens(history) > max_tokens:
        dropped.append(history.pop(0))
    return dropped, history


def _compact_history(
    history: list[dict], *, limit: int, max_tokens: int
) -> list[dict]:
    """compaction 纯函数（与 DB 无关，便于单测）：仅丢弃最旧轮次（P1 行为）。

    1) 硬消息数上限：仅保留最近 ``limit`` 条；
    2) token 预算护栏：从最旧轮次起丢弃，直到不超 ``max_tokens`` 或仅剩 1 条。
    短对话（未触任一上限）保持原顺序与内容不变。
    """
    _, kept = _split_compaction(history, limit=limit, max_tokens=max_tokens)
    return kept


def _assemble_summary(kept: list[dict], summary: str) -> list[dict]:
    """把摘要以 user 角色、带前缀注入历史最前（不破坏 {role, content} 形状）。"""
    return [{"role": "user", "content": f"{SUMMARY_PREFIX} {summary}"}] + kept


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
    history = _read_history(session, conv_id)
    return _compact_history(history, limit=limit, max_tokens=max_tokens)


async def load_chat_history_with_summary(
    session: Session,
    conv_id: UUID,
    *,
    limit: int = 20,
    max_tokens: int = CHAT_HISTORY_MAX_TOKENS,
    summarize: "Callable[[list[dict]], Awaitable[str | None]] | None" = None,
) -> list[dict]:
    """载入历史；compaction 需丢弃最旧轮次时改以摘要注入（自动摘要，P2）。

    - ``summarize`` 为 ``async (dropped) -> str | None``：提供则对被丢弃轮次生成一句摘要，
      以 user 角色 + ``[历史摘要]`` 前缀前置注入；调用抛异常或返回 None 时**回退 P1 纯丢弃**，
      绝不因摘要失败而破坏上下文。
    - 不提供 ``summarize`` 时退化为 :func:`load_chat_history`（纯丢弃）。
    - 短对话（未触任一上限）不调用 ``summarize``，行为与 P1 完全一致。
    """
    history = _read_history(session, conv_id)
    dropped, kept = _split_compaction(history, limit=limit, max_tokens=max_tokens)
    if dropped and summarize:
        try:
            summary = await summarize(dropped)
        except Exception:
            summary = None
        if summary:
            kept = _assemble_summary(kept, summary)
    return kept


__all__ = [
    "get_conversation_by_id",
    "next_turn",
    "load_chat_history",
    "load_chat_history_with_summary",
]
