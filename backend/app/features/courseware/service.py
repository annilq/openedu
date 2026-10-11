"""课件服务编排（ADR-0067 切片 3）：列表 / 新建 / 读 / 改 / 覆盖写环节 / 删。

两条纪律贯穿本模块：

1. **内容由教师手动编辑，服务端不产内容**：环节的增 / 删 / 改序 / 改内容全在前端完成，
   后端只经 ``PUT /sections`` 整体覆盖写存结果（ADR-0085：AI 起草已移除，本模块
   不再调模型、也不再有「未配模型」这一失败面）。新建即建一份**零环节**课件。
2. **归属只经 ``core.guard``**：取课件 / 取知识点都走 ``require_owned``，本模块
   不内联比较 ``teacher_id``（分层不变量 9）。
"""

from __future__ import annotations

import uuid

from sqlmodel import Session

from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned
from app.db.models import (
    COURSEWARE_STATUSES,
    Courseware,
    KnowledgePoint,
    get_datetime_utc,
)
from app.db.models.courseware import COURSEWARE_STATUS_DRAFT
from app.features.courseware import repository as repo
from app.features.courseware.schemas import (
    CoursewareCreate,
    CoursewareResp,
    CoursewareSection,
    CoursewareSectionsUpdate,
    CoursewareUpdate,
)

# ── 环节校验 ────────────────────────────────────────────────────────────


def _store_sections(sections: list[CoursewareSection]) -> list[dict] | None:
    """环节序列 → 落库形态。

    ⚠️ 空列表一律写成 ``None``（真 SQL NULL）：该列是 ``JSON(none_as_null=True)``，
    写 ``[]`` 会让「有环节吗」的判断退化成「列表是不是空」两种口径；写 NULL 后
    ``sections IS NULL`` 就是唯一的空语义（ADR-0061 §N / ADR-0067 §3.2）。
    """
    if not sections:
        return None
    return [_section_to_dict(s) for s in sections]


def _section_to_dict(s: CoursewareSection) -> dict:
    return {
        "id": s.id or uuid.uuid4().hex[:8],
        "title": s.title,
        "script": s.script,
        # T02：话术多段化——整列覆盖写时把段列表一并落库（不丢字段）。
        "script_segments": [
            {"text": seg.text, "emphasis": seg.emphasis}
            for seg in (s.script_segments or [])
        ],
        "payload": s.payload or {},
        # 内容块统一化：素材 / 场景是顶层字段（旧数据这两键缺失，落库
        # 为缺省值，前端回退 payload 内嵌；新数据优先走顶层字段）。
        "materials": s.materials or [],
        "scene": s.scene,
        # courseware-round-3 T06：练习是第四可选内容块（与 materials / scene 并列），
        # 顶层字段，旧数据走 payload['qtype'] 由前端回退读取。
        "practice": s.practice,
    }


def _fill_ids(sections: list[CoursewareSection]) -> list[CoursewareSection]:
    """前端新建环节时不必预先发号——空的 id 由后端补（同份课件内唯一）。"""
    for s in sections:
        if not s.id:
            s.id = uuid.uuid4().hex[:8]
    return sections


# ── 响应装配 ────────────────────────────────────────────────────────────


def _resp(
    session: Session, *, teacher_id: uuid.UUID, courseware: Courseware
) -> CoursewareResp:
    sections = _read_sections(courseware)
    return CoursewareResp(
        id=courseware.id,
        subject=courseware.subject,
        grade=courseware.grade,
        semester=courseware.semester,
        knowledge_point_id=courseware.knowledge_point_id,
        kp_name=courseware.kp_name,
        title=courseware.title,
        status=courseware.status,
        sections=sections,
        section_count=len(sections),
        kp_missing=_kp_missing(
            session, teacher_id=teacher_id, kp_id=courseware.knowledge_point_id
        ),
        created_at=courseware.created_at,
        updated_at=courseware.updated_at,
    )


def _read_sections(courseware: Courseware) -> list[CoursewareSection]:
    """库里的 JSON → 环节列表。``None`` / 非列表一律给 ``[]``（配合计数 0）。"""
    raw = courseware.sections
    if not isinstance(raw, list):
        return []
    out: list[CoursewareSection] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        try:
            out.append(CoursewareSection.model_validate(item))
        except Exception:  # noqa: BLE001 — 单个脏环节不该让整份课件读不出来
            continue
    return out


def _kp_missing(
    session: Session, *, teacher_id: uuid.UUID, kp_id: uuid.UUID | None
) -> bool:
    """该课件所属知识点是不是已经没了（ADR-0067 §4.1 孤儿课件标注）。

    课件**不级联删除**：它是教师调过的资产。知识点被清理后靠 ``kp_name`` 快照
    继续展示，列表行据此标注「所属知识点已移除」。
    """
    if kp_id is None:
        return True
    alive = repo.existing_knowledge_point_ids(session, teacher_id=teacher_id, ids=[kp_id])
    return kp_id not in alive


# ── 端点编排 ────────────────────────────────────────────────────────────


def list_coursewares(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    knowledge_point_id: uuid.UUID | None = None,
    subject: str | None = None,
    grade: int | None = None,
    semester: str | None = None,
) -> list[CoursewareResp]:
    rows = repo.list_courseware(
        session,
        teacher_id=teacher_id,
        knowledge_point_id=knowledge_point_id,
        subject=subject,
        grade=grade,
        semester=semester,
    )
    return [_resp(session, teacher_id=teacher_id, courseware=c) for c in rows]


def recent_courseware(
    session: Session, *, teacher_id: uuid.UUID
) -> CoursewareResp | None:
    """最近更新的那一份（ADR-0067 §3.8「最近课件」回执）；没有则 ``None``。"""
    row = repo.recent_courseware(session, teacher_id=teacher_id)
    return _resp(session, teacher_id=teacher_id, courseware=row) if row else None


def get_courseware(
    session: Session, *, teacher_id: uuid.UUID, courseware_id: uuid.UUID
) -> CoursewareResp:
    row = repo.get_owned_courseware(
        session, teacher_id=teacher_id, courseware_id=courseware_id
    )
    return _resp(session, teacher_id=teacher_id, courseware=row)


def create_courseware(
    session: Session, *, teacher_id: uuid.UUID, req: CoursewareCreate
) -> CoursewareResp:
    """新建课件：按知识点快照建一份**零环节空壳**（ADR-0085：不再 AI 起草）。

    - 知识点行经 ``core.guard`` 取（不存在 / 非本人 → ``COURSEWARE_KP_NOT_FOUND``）；
    - ``kp_name`` / ``subject`` / ``grade`` / ``semester`` **快照**到课件行，展示
      不依赖 join（§3.2）；
    - 零环节写成真 SQL NULL（同 ``_store_sections``）；``objective``（教学目标 / 备注）
      落到课件行供编辑页展示。内容由教师随后手动增删环节（``PUT /sections``）。
    """
    kp: KnowledgePoint = require_owned(
        session=session,
        owner_id=teacher_id,
        model=KnowledgePoint,
        obj_id=req.knowledge_point_id,
        code=ErrCode.COURSEWARE_KP_NOT_FOUND,
        message="知识点不存在或无权访问",
    )
    courseware = Courseware(
        teacher_id=teacher_id,
        subject=kp.subject,
        grade=kp.grade,
        semester=kp.semester,
        knowledge_point_id=kp.id,
        kp_name=kp.name,
        title=req.title or kp.name,
        status=COURSEWARE_STATUS_DRAFT,
        objective=req.objective,
        sections=None,
    )
    row = repo.add_courseware(session, courseware=courseware)
    return _resp(session, teacher_id=teacher_id, courseware=row)


def update_courseware(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    courseware_id: uuid.UUID,
    req: CoursewareUpdate,
) -> CoursewareResp:
    """改标题 / 状态。只传要改的字段（``None`` = 不动）。"""
    row = repo.get_owned_courseware(
        session, teacher_id=teacher_id, courseware_id=courseware_id
    )
    if req.title is not None:
        row.title = req.title
    if req.status is not None:
        if req.status not in COURSEWARE_STATUSES:
            raise AppErrorException(
                ErrCode.VALIDATION,
                f"未知的课件状态：{req.status}（只能是 {' / '.join(COURSEWARE_STATUSES)}）",
            )
        row.status = req.status
    # 动过就要顶到「最近课件」第一位：回执的意义是「继续上次」（建库时列的
    # updated_at 只在插入时取一次，改动不写它的话回执会一直指向最早那份）。
    row.updated_at = get_datetime_utc()
    row = repo.save_courseware(session, courseware=row)
    return _resp(session, teacher_id=teacher_id, courseware=row)


def replace_sections(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    courseware_id: uuid.UUID,
    req: CoursewareSectionsUpdate,
) -> CoursewareResp:
    """整体覆盖写环节序列（排序 / 增删改都在前端完成，后端只存结果）。

    环节统一为内容块容器（T07 起无 kind 字段）；空列表落真 SQL NULL。
    """
    row = repo.get_owned_courseware(
        session, teacher_id=teacher_id, courseware_id=courseware_id
    )
    sections = _fill_ids(list(req.sections or []))
    row.sections = _store_sections(sections)
    row.updated_at = get_datetime_utc()
    row = repo.save_courseware(session, courseware=row)
    return _resp(session, teacher_id=teacher_id, courseware=row)


def delete_courseware(
    session: Session, *, teacher_id: uuid.UUID, courseware_id: uuid.UUID
) -> None:
    row = repo.get_owned_courseware(
        session, teacher_id=teacher_id, courseware_id=courseware_id
    )
    repo.delete_courseware(session, courseware=row)
