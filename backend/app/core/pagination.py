"""游标（keyset）分页基建：三个长列表共用的排序键、游标编解码与取页工具。

为什么不用 offset：题库 / 任务 / 错题本都是「新数据从顶部插入」（排序键 created_at
倒序）。offset 分页在两次请求之间插入一行就会重复或漏掉一条——用户表现为「这道题
出现了两次」。游标分页锚定上一批最后一条的排序键值，插入只影响新数据所在的一侧。

排序键 = ``(coalesce(created_at, epoch) DESC, id DESC)``：

- ``id`` 是决胜键——同一时间戳（批量导入 / 同一秒内生成）下没有它，页界处会不稳定。
- ``coalesce`` 是跨库一致性的需要：SQLite 把 NULL 当最小值、PostgreSQL 把 NULL 当
  最大值，``ORDER BY created_at DESC`` 在两库下 NULL 行的位置**相反**。统一 coalesce
  到 epoch 后，NULL 行在两库都排在最后，游标比较也随之确定。
  代价是该表达式用不上 ``(parent_id, created_at)`` 索引；本应用单库规模在千级，
  正确性优先于索引命中。

游标是不透明字符串（URL-safe base64），客户端只能原样回传，不得解析。
"""
from __future__ import annotations

import base64
import binascii
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import Select, and_, func, or_
from sqlalchemy.orm import InstrumentedAttribute
from sqlalchemy.sql.elements import ColumnElement
from sqlmodel import Session, select

# ── 分页档位 ──
DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 100

# NULL created_at 的排序替身：任何真实时间戳都晚于它，故 NULL 行恒在末尾。
_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)

_SEP = "|"


def timestamp_key(column: InstrumentedAttribute[datetime | None]) -> ColumnElement[datetime]:
    """排序用的时间戳键：NULL 归一到 epoch（见模块 docstring）。"""
    return func.coalesce(column, _EPOCH)


def encode_cursor(*, created_at: datetime | None, id_: UUID) -> str:
    """把上一批最后一条的排序键编成不透明游标。

    ``created_at`` 为 None 表示那一行没有时间戳（旧数据），游标里记为 epoch，
    与 :func:`timestamp_key` 的排序口径一致。
    """
    ts = (created_at or _EPOCH).isoformat()
    raw = f"{ts}{_SEP}{id_}".encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def decode_cursor(cursor: str | None) -> tuple[datetime, UUID] | None:
    """解游标。``None`` / 空串 / 非法串一律返回 ``None``（当作「从头开始」）。

    非法串不抛错：游标来自查询参数，用户可能手改、也可能拿到过期游标。静默退化为
    「第一页」比 500 更符合预期——最坏情况是看到重复数据，不会崩。
    """
    if not cursor:
        return None
    padded = cursor + "=" * (-len(cursor) % 4)
    try:
        raw = base64.urlsafe_b64decode(padded.encode()).decode()
        ts_text, _, id_text = raw.partition(_SEP)
        if not ts_text or not id_text:
            return None
        return datetime.fromisoformat(ts_text), UUID(id_text)
    except (ValueError, binascii.Error, UnicodeDecodeError):
        return None


def order_by_keyset(
    ts_column: InstrumentedAttribute[datetime | None],
    id_column: InstrumentedAttribute[UUID],
) -> tuple[ColumnElement[datetime], ColumnElement[UUID]]:
    """稳定排序键：时间戳倒序 + id 倒序决胜。"""
    return timestamp_key(ts_column).desc(), id_column.desc()


def apply_keyset(
    stmt: Select,
    *,
    ts_column: InstrumentedAttribute[datetime | None],
    id_column: InstrumentedAttribute[UUID],
    cursor: str | None,
) -> Select:
    """给查询加游标条件与稳定排序。

    条件形如 ``(ts < c_ts) OR (ts == c_ts AND id < c_id)``——即「排在上一批最后一条
    之后的所有行」，与 :func:`order_by_keyset` 的排序严格互逆。
    """
    stmt = stmt.order_by(*order_by_keyset(ts_column, id_column))
    decoded = decode_cursor(cursor)
    if decoded is None:
        return stmt
    c_ts, c_id = decoded
    ts = timestamp_key(ts_column)
    return stmt.where(or_(ts < c_ts, and_(ts == c_ts, id_column < c_id)))


def clamp_page_size(page_size: int | None) -> int:
    """把 page_size 钳到 [1, MAX_PAGE_SIZE]，缺省取默认值。"""
    if page_size is None:
        return DEFAULT_PAGE_SIZE
    return max(1, min(page_size, MAX_PAGE_SIZE))


def count_of(*, session: Session, stmt: Select) -> int:
    """``SELECT COUNT(*)``——不要 ``len(session.exec(stmt).all())``。

    后者把全部行读进内存只为数个数，分页省下的 IO 又赔在计数上。
    """
    return session.exec(select(func.count()).select_from(stmt.subquery())).one()
