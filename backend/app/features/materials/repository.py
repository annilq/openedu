"""资料库数据访问（ADR-0055）：查询与级联删除集中在此，service 只做编排。

归属判断不在本层——router / service 经 ``core.guard``（require_owned /
find_owned）拿行，本层只做**已知 owner** 下的集合查询。
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence

from sqlmodel import Session, func, select

from app.core.guard import require_owned
from app.db.models import KnowledgePoint, Material, MaterialChunk, MaterialFolder
from app.db.models.material import (
    INDEX_STATE_FAILED,
    INDEX_STATE_PENDING,
    INDEX_STATE_STALE,
    KP_SOURCE_EMERGED,
    KP_SOURCE_SKELETON,
    KP_STATUS_CURATED,
    KP_STATUS_PENDING,
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


def prunable_knowledge_points(
    session: Session,
    *,
    parent_id: uuid.UUID,
    candidates: Iterable[tuple[str, int, str, str]],
    exclude_material_ids: set[uuid.UUID] = frozenset(),
) -> list[KnowledgePoint]:
    """从候选 (学科, 年级, 学期, 名字) 里挑出**可以安全删除**的知识点行。

    删除资料 ≠ 删除知识点：它们之间没有外键，只有 ``Material.knowledge_points``
    里的名字字符串，而同一个名字会被多份资料共享（涌现走 upsert）。所以判定
    必须同时满足三条，缺一不可：

    1. **按名/os 作用域定位**：只有同 (学科, 年级, 学期) 的那一行算「这份资料
       的那一个」，不同学期是各自独立的知识点（各自配讲解模板）。
    2. **没有别的资料还在引用**：只要还有任一留存资料的知识清单里有这个名字
       （同 学科+年级，跨学期也算），就说明该知识点另有来源，不能删。
    3. **从未被家长接管**：只删 ``source=emerged`` 且 ``status=pending`` 的行。
       已转正（curated）说明家长显式确认过、可能还配好了讲解模板——那是家长
       的资产，删资料不该顺手抹掉；他要删请到「知识点管理」里手动删。
    """
    wanted: list[tuple[str, int, str, str]] = []
    seen: set[tuple[str, int, str, str]] = set()
    for subject, grade, semester, name in candidates:
        key = (subject, grade, semester, name)
        if not name or key in seen:
            continue
        seen.add(key)
        wanted.append(key)
    if not wanted:
        return []

    # 2. 留存资料仍在引用的 (学科, 年级, 名字)——跨学期并集，宁可保守不删。
    still_used: set[tuple[str, int, str]] = set()
    rows = session.exec(
        select(
            Material.id,
            Material.subject,
            Material.grade,
            Material.knowledge_points,
        ).where(Material.parent_id == parent_id)
    ).all()
    for material_id, subject, grade, kps in rows:
        if not subject or not grade or not kps:
            continue
        if exclude_material_ids and material_id in exclude_material_ids:
            continue
        for name in kps:
            still_used.add((subject, grade, name))

    out: list[KnowledgePoint] = []
    for subject, grade, semester, name in wanted:
        if (subject, grade, name) in still_used:
            continue
        stmt = select(KnowledgePoint).where(
            KnowledgePoint.parent_id == parent_id,
            KnowledgePoint.subject == subject,
            KnowledgePoint.grade == grade,
            KnowledgePoint.semester == semester,
            KnowledgePoint.name == name,
            # 3. 只收回「系统自己涌现、家长从未接管」的行
            KnowledgePoint.source == KP_SOURCE_EMERGED,
            KnowledgePoint.status == KP_STATUS_PENDING,
        )
        out.extend(session.exec(stmt).all())
    return out


def delete_knowledge_points(
    session: Session, *, parent_id: uuid.UUID, ids: list[uuid.UUID]
) -> int:
    """批量删除本家长名下的知识点，返回实际删除条数。

    归属口径就是 ``parent_id``：越权 / 不存在的 id 被这层过滤静默跳过，不会误删
    他人数据（与 ``assistant.delete_conversations`` 同一手法）。
    """
    if not ids:
        return 0
    owned_ids = list(
        session.exec(
            select(KnowledgePoint.id).where(
                KnowledgePoint.parent_id == parent_id,
                KnowledgePoint.id.in_(ids),  # type: ignore[attr-defined]
            )
        ).all()
    )
    if not owned_ids:
        return 0
    rows = session.exec(
        select(KnowledgePoint).where(KnowledgePoint.id.in_(owned_ids))  # type: ignore[attr-defined]
    ).all()
    for kp in rows:
        session.delete(kp)
    session.commit()
    return len(rows)


def count_unindexed(session: Session, *, parent_id: uuid.UUID) -> int:
    """未参与检索的资料数（pending/failed/stale）——出题提示「有 N 份资料未参与」。"""
    stmt = select(Material.id).where(
        Material.parent_id == parent_id,
        Material.index_state.in_(UNINDEXED_STATES),  # type: ignore[attr-defined]
    )
    return len(session.exec(stmt).all())


def delete_material_cascade(
    session: Session,
    material: Material,
    knowledge_points: Sequence[KnowledgePoint] = (),
) -> tuple[int, int]:
    """删资料：片段与向量一并删除（ADR-0055 §9）。返回 (片段数, 知识点数)。

    ``knowledge_points`` 是调用方判定可一并删除的知识点行（孤儿判定在
    :func:`prunable_knowledge_points`）——资料与知识点之间**没有外键**，链接只有
    名字字符串，所以能不能删必须由 service 层按作用域算清楚后传进来。
    """
    chunks = session.exec(
        select(MaterialChunk).where(MaterialChunk.material_id == material.id)
    ).all()
    for chunk in chunks:
        session.delete(chunk)
    for kp in knowledge_points:
        session.delete(kp)
    session.delete(material)
    session.commit()
    return len(chunks), len(knowledge_points)


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


def confirm_knowledge_points_by_name(
    session: Session,
    *,
    parent_id: uuid.UUID,
    subject: str,
    grade: int,
    names: list[str],
    semester: str = "",
) -> int:
    """按概念名跨学期转正（修复 ADR-0055 §4 的确认盲区）。

    同一 ``(parent_id, subject, grade, name)`` 可能按学期拆成多行——整学年 / 上学期 /
    下学期各一份（支持各学期独立讲解模板，见 ``scene_fusion`` 的学期回落）。家长在
    「整学年」视图确认某个概念时，应当把该名下**所有**学期行的 ``pending`` 一并转正，
    而不是只翻当前筛选学期那一行。旧实现按 ``semester`` 精确 ``find``，导致同名其它
    学期的待审永远翻不动，列表里长期并存「待审 + 已转正」两条同名数据。

    ``semester`` 仅用于名下无行时新建骨架条的默认学期（默认整学年）。
    """
    confirmed = 0
    for raw in names:
        name = raw.strip()[:128]
        if not name:
            continue
        rows = session.exec(
            select(KnowledgePoint).where(
                KnowledgePoint.parent_id == parent_id,
                KnowledgePoint.subject == subject,
                KnowledgePoint.grade == grade,
                KnowledgePoint.name == name,
            )
        ).all()
        if not rows:
            # 名下无行：按 semester 兜底新建一条 curated（骨架来源）。学期必须具体
            # （2026-10-05 决策：不再允许空），整学年视图确认时退上学期。
            kp = KnowledgePoint(
                parent_id=parent_id,
                subject=subject,
                grade=grade,
                semester=semester or "上学期",
                name=name,
                status=KP_STATUS_CURATED,
                source=KP_SOURCE_SKELETON,
            )
            session.add(kp)
            confirmed += 1
        else:
            flipped = False
            for kp in rows:
                if kp.status == KP_STATUS_PENDING:
                    kp.status = KP_STATUS_CURATED
                    flipped = True
                    confirmed += 1
            if flipped:
                session.add_all(rows)
    session.commit()
    return confirmed
