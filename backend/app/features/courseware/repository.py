"""课件数据访问（ADR-0067 切片 3）：查询与落库集中在此，service 只做编排。

归属判定不在本层——service 经 ``core.guard``（``require_owned`` 走
:func:`get_owned_courseware`）拿单行，本层只做**已知 owner** 下的集合查询
（与 ``materials.repository`` 同款分工）。

两点与课件强相关的口径：

- **排序一律 ``updated_at`` 倒序**：列表与「最近课件」回执（ADR-0067 §3.8 的
  强制补偿项）必须同一口径，否则回执指向的课件可能不是列表第一条。
- **知识点只查「还在不在」，不 join**：课件自带 ``kp_name`` 快照，展示不依赖
  知识点行（§4.1 孤儿课件）。查询只为算 ``kp_missing`` 标注。
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable

from sqlmodel import Session, select

from app.core.errors import ErrCode
from app.core.guard import require_owned
from app.db.models import Courseware, KnowledgePoint


def get_owned_courseware(
    session: Session, *, teacher_id: uuid.UUID, courseware_id: uuid.UUID
) -> Courseware:
    """取本教师的课件；不存在与越权同错（COURSEWARE_NOT_FOUND，404）。"""
    return require_owned(
        session=session,
        owner_id=teacher_id,
        model=Courseware,
        obj_id=courseware_id,
        code=ErrCode.COURSEWARE_NOT_FOUND,
        message="课件不存在或无权访问",
    )


def list_courseware(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    knowledge_point_id: uuid.UUID | None = None,
    subject: str | None = None,
    grade: int | None = None,
    semester: str | None = None,
) -> list[Courseware]:
    """本人的课件列表（四个范围维度全可空 = 全部），按 ``updated_at`` 倒序。

    范围来自**课件行的快照**（建课件时从知识点拷过来），不 join 知识点表：
    知识点被 ADR-0064 清理后课件仍在，按快照照样筛得到（§4.1）。
    """
    stmt = select(Courseware).where(Courseware.teacher_id == teacher_id)
    if knowledge_point_id is not None:
        stmt = stmt.where(Courseware.knowledge_point_id == knowledge_point_id)
    if subject is not None:
        stmt = stmt.where(Courseware.subject == subject)
    if grade is not None:
        stmt = stmt.where(Courseware.grade == grade)
    if semester is not None:
        stmt = stmt.where(Courseware.semester == semester)
    return list(session.exec(stmt.order_by(Courseware.updated_at.desc())).all())


def recent_courseware(session: Session, *, teacher_id: uuid.UUID) -> Courseware | None:
    """最近更新的那一份课件（没有则 ``None``）——「最近课件」回执的数据源。"""
    rows = list_courseware(session, teacher_id=teacher_id)
    return rows[0] if rows else None


def existing_knowledge_point_ids(
    session: Session, *, teacher_id: uuid.UUID, ids: Iterable[uuid.UUID]
) -> set[uuid.UUID]:
    """这批知识点 id 里**仍属于本人且仍存在**的集合（供 ``kp_missing`` 标注）。

    一次查询而非逐行 ``session.get``：列表页要为每份课件算一次标注，逐行查会
    退化成 N+1。归属口径就是 ``teacher_id`` 过滤（与 ``assistant`` 批量删会话
    同一手法）。
    """
    wanted = [i for i in ids if i is not None]
    if not wanted:
        return set()
    rows = session.exec(
        select(KnowledgePoint.id).where(
            KnowledgePoint.teacher_id == teacher_id,
            KnowledgePoint.id.in_(wanted),  # type: ignore[attr-defined]
        )
    ).all()
    return set(rows)


def add_courseware(session: Session, *, courseware: Courseware) -> Courseware:
    session.add(courseware)
    session.commit()
    session.refresh(courseware)
    return courseware


def save_courseware(session: Session, *, courseware: Courseware) -> Courseware:
    session.add(courseware)
    session.commit()
    session.refresh(courseware)
    return courseware


def delete_courseware(session: Session, *, courseware: Courseware) -> None:
    session.delete(courseware)
    session.commit()
