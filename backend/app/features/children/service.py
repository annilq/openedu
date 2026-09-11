"""Children feature service：孩子列表。

「家长↔娃娃归属校验」已上提为 ``app.core.guard.require_owned_child``，由 REST
路由、service 与 ADR-0033 的业务查询工具**共用同一份**——本模块不再持有一份。
"""

from __future__ import annotations

from uuid import UUID

from sqlmodel import Session

from app.db.models import User
from app.features.auth.repository import list_children


def list_children_of(*, session: Session, parent_id: UUID) -> list[User]:
    """家长名下全部娃娃。

    收口「孩子列表」的读取口径：查询工具不得跨 feature 直连 ``auth`` 仓储
    （ADR-0033 决策 13）。
    """
    return list_children(session=session, parent_id=parent_id)
