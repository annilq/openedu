"""Repository layer for the assistant (悬浮助手) feature.

多轮会话复用与历史读取（ADR-0026）：前端只需带 ``session_id``，后端按 id 取回
``Conversation`` 并载入历史消息拼入 prompt，维持多轮上下文。

同一批行还被读成**用户面的会话历史**（ADR-0048）：列表（家长名下的会话，含娃娃的）
与回放（把落库轨迹折回对话气泡）。两条读路径与 prompt 历史共用同一个「可见轮次」
判定（:func:`_visible_rows`）——「哪些行算一轮对话」是领域判定，只应有一份。
"""
from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any
from uuid import UUID

from sqlmodel import Session, func, select

from app.db.models import Conversation, Message, User

# compaction（P1/P2）护栏：超过则丢弃最旧轮次，避免长推理对话撑爆 prompt。
# 经验保守值，仅做「不溢出」上界；精确计费交给模型方。
CHAT_HISTORY_MAX_TOKENS = 4000
# 单条消息 token 估算开销（角色 / 结构），与内容按 ~4 字符 / token 累加。
_MSG_TOKEN_OVERHEAD = 4
# 自动摘要（P2）注入前缀：history 下游约定 role 仅 user/assistant（ports.py），
# 故摘要以 user 角色 + 前缀注入，不破坏 {role, content} 形状，且能被所有 provider 消费。
SUMMARY_PREFIX = "[历史摘要]"

# 会话命名（ADR-0048）：取首条用户消息截断。它是用户**自己认得的第一句**，零额外模型
# 调用、零新字段；模型生成标题更好看，但要在首轮多挂一次调用并处理失败回退，
# 而标题并非必需项（对比 compaction 摘要——那是上下文连续性的必需项）。
CONVERSATION_TITLE_MAX = 20
# 无任何可命名来源时的落点（理论上不可达：会话必然由一条用户消息建立）。
UNTITLED_CONVERSATION = "新的对话"


def derive_title(message: str) -> str:
    """会话命名 = 首条用户消息折叠空白后截断（写入侧）。"""
    return " ".join((message or "").split())[:CONVERSATION_TITLE_MAX]


def title_of(conv: Conversation, first_user: str) -> str:
    """列表行名（读出侧）：落库的 title 优先，缺失时回落首条用户发言。

    回落不是可选的兼容层：会话命名随本特性引入，**此前建立的会话 title 全为 NULL**
    （该字段自 ADR-0022 起就是死字段），没有回落它们会全部显示成空行。
    """
    return (
        conv.title or first_user.strip() or UNTITLED_CONVERSATION
    )[:CONVERSATION_TITLE_MAX]


def _estimate_tokens(history: list[dict]) -> int:
    """粗估历史 token 数：内容按 ~4 字符 / token + 单条结构开销。"""
    return sum(len(m.get("content") or "") // 4 + _MSG_TOKEN_OVERHEAD for m in history)


def _visible_rows(session: Session, conv_id: UUID) -> list[Message]:
    """会话内的**可见轮次**（user 输入 + assistant 输出），按 ``turn`` 升序。

    「可见」是领域判定而非 SQL 细节：``system/routing`` 与 ``tool/*`` 是运行轨迹，
    不属于对话内容。prompt 历史与用户面回放共用本查询——同一口径写两遍，
    迟早会出现「喂给模型的上下文」与「回放给用户的气泡」不一致。

    ``turn`` 是**唯一排序键**，它必须全局单调（跨轮不撞号）才有意义，
    见 ``service.chat`` 的 turn 起点与 `tests/api/routes/test_assistant.py` 的守卫。
    """
    return list(
        session.exec(
            select(Message)
            .where(
                Message.conversation_id == conv_id,
                Message.role.in_(["user", "assistant"]),
                Message.step.in_(["input", "output"]),
            )
            .order_by(Message.turn.asc())
        ).all()
    )


def _read_history(session: Session, conv_id: UUID) -> list[dict]:
    """读取会话原始历史（user 输入 + assistant 输出）为 [{role, content}]。"""
    return [
        {"role": m.role, "content": m.content or ""}
        for m in _visible_rows(session, conv_id)
    ]


def read_conversation_bubbles(session: Session, conv_id: UUID) -> list[dict]:
    """把落库轨迹折回对话气泡（用户面回放，ADR-0048）。

    卡片取自 assistant 输出行 ``payload["cards"]``——落库时存的是 DATA **整帧**
    （判别键 + 载荷），故可原样交给前端按种类分派回渲染器（ADR-0042 当初把整帧落库
    就是为这一步留的口子）。

    不做二次过滤：可见行与气泡是**一一对应**的——assistant 输出行只在
    ``final_text or cards`` 成立时才落库（见 ``service.chat`` 的收尾），
    故不存在「无正文无卡片」的空输出行。因此本函数返回的条数就等于会话的可见轮次数。
    """
    return [
        {"role": m.role, "text": m.content or "", "cards": _cards_of(m)}
        for m in _visible_rows(session, conv_id)
    ]


def _cards_of(m: Message) -> list[dict]:
    """assistant 输出行的 DATA 卡片；畸形载荷按「无卡片」处理，不抛错。"""
    if m.role != "assistant" or not isinstance(m.payload, dict):
        return []
    cards = m.payload.get("cards")
    if not isinstance(cards, list):
        return []
    return [c for c in cards if isinstance(c, dict)]


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


# ── 会话列表（用户面，ADR-0048） ─────────────────────────────────────────────
def list_chat_conversations(
    *, session: Session, parent_id: UUID, limit: int = 50
) -> list[Conversation]:
    """家长名下的会话（**含名下娃娃的**），按最近活动倒序。

    归属口径就是 ``Conversation.parent_id``：家长自己聊的 ``child_id IS NULL``，
    娃娃聊的是娃娃的 id（见 ``service.chat`` 的角色分流）。这里不在 SQL 里再按
    ``child_id`` 过滤——两类条目都要，「我的 / 孩子的」怎么分段是展示层的事。

    排序键取 ``updated_at``（会话每次被读写都会刷新）而非 ``created_at``：
    刚被续接过的旧会话应该浮到最上面，否则续接完回到列表还得往下翻。
    """
    return list(
        session.exec(
            select(Conversation)
            .where(Conversation.parent_id == parent_id)
            .order_by(Conversation.updated_at.desc(), Conversation.created_at.desc())
            .limit(limit)
        ).all()
    )


def conversation_meta(
    session: Session, conv_ids: list[UUID]
) -> dict[UUID, dict[str, Any]]:
    """每个会话的列表元信息：可见轮次数 + 首条用户发言（title 的回落来源）。

    一次查询取回全部可见行的三列，在内存里按会话归并——按 ``turn`` 升序取即得
    「首条用户发言」，无需子查询 / 窗口函数。查询规模被 ``limit`` 的会话数框住。
    """
    out: dict[UUID, dict[str, Any]] = {}
    if not conv_ids:
        return out
    rows = session.exec(
        select(Message.conversation_id, Message.role, Message.content)
        .where(
            Message.conversation_id.in_(conv_ids),
            Message.role.in_(["user", "assistant"]),
            Message.step.in_(["input", "output"]),
        )
        .order_by(Message.conversation_id, Message.turn.asc())
    ).all()
    for cid, role, content in rows:
        meta = out.setdefault(cid, {"bubble_count": 0, "first_user": ""})
        meta["bubble_count"] += 1
        if role == "user" and not meta["first_user"]:
            meta["first_user"] = content or ""
    return out


def child_names(session: Session, child_ids: list[UUID]) -> dict[UUID, str]:
    """娃娃 id → 显示名（列表行的归属标签）。"""
    ids = [cid for cid in child_ids if cid is not None]
    if not ids:
        return {}
    rows = session.exec(select(User.id, User.display_name).where(User.id.in_(ids))).all()
    return {uid: name for uid, name in rows}


__all__ = [
    "get_conversation_by_id",
    "next_turn",
    "load_chat_history",
    "load_chat_history_with_summary",
    "derive_title",
    "title_of",
    "read_conversation_bubbles",
    "list_chat_conversations",
    "conversation_meta",
    "child_names",
]
