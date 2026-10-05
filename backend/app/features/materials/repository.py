"""资料库数据访问（ADR-0055）：查询与级联删除集中在此，service 只做编排。

归属判断不在本层——router / service 经 ``core.guard``（require_owned /
find_owned）拿行，本层只做**已知 owner** 下的集合查询。
"""

from __future__ import annotations

import uuid

from sqlmodel import Session, func, select

from app.core.guard import require_owned
from app.db.models import KnowledgePoint, Material, MaterialChunk, MaterialFolder
from app.db.models.material import (
    INDEX_STATE_FAILED,
    INDEX_STATE_PENDING,
    INDEX_STATE_STALE,
)

UNINDEXED_STATES = (INDEX_STATE_PENDING, INDEX_STATE_FAILED, INDEX_STATE_STALE)


def get_owned_folder(
    session: Session, *, parent_id: uuid.UUID, folder_id: uuid.UUID
) -> MaterialFolder:
    # 不存在与越权抛同一错误（guard 纪律：不把越权降级成「不存在」），默认 403。
    return require_owned(
        session=session,
        owner_id=parent_id,
        model=MaterialFolder,
        obj_id=folder_id,
        message="目录不存在或无权访问",
    )


def get_owned_material(
    session: Session, *, parent_id: uuid.UUID, material_id: uuid.UUID
) -> Material:
    return require_owned(
        session=session,
        owner_id=parent_id,
        model=Material,
        obj_id=material_id,
        message="资料不存在或无权访问",
    )


def list_folders(session: Session, *, parent_id: uuid.UUID) -> list[MaterialFolder]:
    stmt = (
        select(MaterialFolder)
        .where(MaterialFolder.parent_id == parent_id)
        .order_by(MaterialFolder.created_at)
    )
    return list(session.exec(stmt).all())


def folder_counts(
    session: Session, *, parent_id: uuid.UUID
) -> dict[uuid.UUID, tuple[int, int]]:
    """{folder_id: (直接资料数, 直接子目录数)}——一次聚合，列表页免 N+1。"""
    mat_counts: dict[uuid.UUID, int] = {}
    rows = session.exec(
        select(Material.folder_id, func.count(Material.id))
        .where(Material.parent_id == parent_id)
        .group_by(Material.folder_id)
    ).all()
    for folder_id, count in rows:
        if folder_id is not None:
            mat_counts[folder_id] = count
    sub_counts: dict[uuid.UUID, int] = {}
    rows = session.exec(
        select(MaterialFolder.parent_folder_id, func.count(MaterialFolder.id))
        .where(MaterialFolder.parent_id == parent_id)
        .group_by(MaterialFolder.parent_folder_id)
    ).all()
    for parent_folder_id, count in rows:
        if parent_folder_id is not None:
            sub_counts[parent_folder_id] = count
    return {
        fid: (mat_counts.get(fid, 0), sub_counts.get(fid, 0))
        for fid in set(mat_counts) | set(sub_counts)
    }


def count_folder_materials(
    session: Session, *, parent_id: uuid.UUID, folder_id: uuid.UUID
) -> int:
    return len(
        session.exec(
            select(Material.id).where(
                Material.parent_id == parent_id, Material.folder_id == folder_id
            )
        ).all()
    )


def list_materials(
    session: Session,
    *,
    parent_id: uuid.UUID,
    folder_id: uuid.UUID | None = None,
) -> list[Material]:
    stmt = select(Material).where(Material.parent_id == parent_id)
    if folder_id is not None:
        stmt = stmt.where(Material.folder_id == folder_id)
    return list(session.exec(stmt.order_by(Material.created_at.desc())).all())


def count_unindexed(session: Session, *, parent_id: uuid.UUID) -> int:
    """未参与检索的资料数（pending/failed/stale）——出题提示「有 N 份资料未参与」。"""
    stmt = select(Material.id).where(
        Material.parent_id == parent_id,
        Material.index_state.in_(UNINDEXED_STATES),  # type: ignore[attr-defined]
    )
    return len(session.exec(stmt).all())


def delete_material_cascade(session: Session, material: Material) -> int:
    """删资料：片段与向量一并删除（ADR-0055 §9）。返回删除的片段数。"""
    chunks = session.exec(
        select(MaterialChunk).where(MaterialChunk.material_id == material.id)
    ).all()
    for chunk in chunks:
        session.delete(chunk)
    session.delete(material)
    session.commit()
    return len(chunks)


# ── 知识点目录 ──────────────────────────────────────────────────────────


def list_knowledge_points(
    session: Session,
    *,
    parent_id: uuid.UUID,
    subject: str,
    grade: int,
    semester: str = "",
) -> list[KnowledgePoint]:
    """某学科某年级的知识点目录。

    学期语义（ADR-0061 发布任务对接资料库）：
    - ``semester=''`` = **不限学期** → 返回该 (学科, 年级) 下**所有**学期的知识点。
      早期实现按 ``semester == ''`` 精确匹配，而资料涌现出的知识点几乎都带
      「上/下学期」，于是「不限学期」永远返回空——布置任务表单默认态看不到任何
      真实知识点、只剩骨架兜底，看起来就像「知识点不随学期切换」。
    - ``semester='上/下学期'`` → 精确匹配该学期（家长明确限定了学期就该只看它）。
    """
    stmt = select(KnowledgePoint).where(
        KnowledgePoint.parent_id == parent_id,
        KnowledgePoint.subject == subject,
        KnowledgePoint.grade == grade,
    )
    if semester:
        stmt = stmt.where(KnowledgePoint.semester == semester)
    stmt = stmt.order_by(KnowledgePoint.semester, KnowledgePoint.created_at)
    return list(session.exec(stmt).all())


def find_knowledge_point(
    session: Session,
    *,
    parent_id: uuid.UUID,
    subject: str,
    grade: int,
    name: str,
    semester: str = "",
) -> KnowledgePoint | None:
    stmt = select(KnowledgePoint).where(
        KnowledgePoint.parent_id == parent_id,
        KnowledgePoint.subject == subject,
        KnowledgePoint.grade == grade,
        KnowledgePoint.semester == semester,
        KnowledgePoint.name == name,
    )
    return session.exec(stmt).first()


def upsert_pending_knowledge_point(
    session: Session,
    *,
    parent_id: uuid.UUID,
    subject: str,
    grade: int,
    name: str,
    semester: str = "",
) -> KnowledgePoint:
    """涌现知识点落库：已存在则原样返回（不动状态），不存在则新建**待审**。"""
    existing = find_knowledge_point(
        session,
        parent_id=parent_id,
        subject=subject,
        grade=grade,
        name=name,
        semester=semester,
    )
    if existing is not None:
        return existing
    kp = KnowledgePoint(
        parent_id=parent_id,
        subject=subject,
        grade=grade,
        semester=semester,
        name=name,
    )
    session.add(kp)
    session.commit()
    session.refresh(kp)
    return kp


def confirm_knowledge_point(session: Session, kp: KnowledgePoint) -> KnowledgePoint:
    kp.status = "curated"
    session.add(kp)
    session.commit()
    session.refresh(kp)
    return kp
