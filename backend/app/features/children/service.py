"""Children feature service：家长↔娃娃归属校验与孩子列表。

归属校验此前在 ``tasks`` / ``mastery`` 路由里各写一份同形判断，漏写一处即越权读。
现收口为 ``require_owned_child``，由 REST 路由与 ADR-0033 的业务查询工具**共用同一份**；
错误码/文案可按调用方覆写，以保持既有响应体不变。
"""

from __future__ import annotations

from uuid import UUID

from sqlmodel import Session

from app.core.errors import AppErrorException, ErrCode
from app.db.models import User
from app.features.auth.repository import list_children


def require_owned_child(
    *,
    session: Session,
    parent: User,
    child_id: UUID,
    code: ErrCode = ErrCode.TASK_NOT_YOUR_CHILD,
    message: str = "该娃娃不属于你的账号",
) -> User:
    """断言 ``child_id`` 是 ``parent`` 名下娃娃，返回该 ``User``；否则抛业务错误。"""
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise AppErrorException(code, message)
    return child


def list_children_of(*, session: Session, parent_id: UUID) -> list[User]:
    """家长名下全部娃娃。

    收口「孩子列表」的读取口径：查询工具不得跨 feature 直连 ``auth`` 仓储
    （ADR-0033 决策 13）。
    """
    return list_children(session=session, parent_id=parent_id)
