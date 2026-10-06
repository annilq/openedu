"""Students feature service：学生列表。

「教师↔学生归属校验」已上提为 ``app.core.guard.require_owned_student``，由 REST
路由、service 与 ADR-0033 的业务查询工具**共用同一份**——本模块不再持有一份。
"""

from __future__ import annotations

from uuid import UUID

from sqlmodel import Session

from app.db.models import User
from app.features.auth.repository import list_students


def list_students_of(*, session: Session, teacher_id: UUID) -> list[User]:
    """教师名下全部学生。

    收口「学生列表」的读取口径：查询工具不得跨 feature 直连 ``auth`` 仓储
    （ADR-0033 决策 13）。
    """
    return list_students(session=session, teacher_id=teacher_id)
