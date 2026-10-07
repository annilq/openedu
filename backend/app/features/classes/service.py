"""班级 service（ADR-0068 / teacher-scale-up 地基）。

归属校验统一走 ``core.guard.require_owned``（分层不变量 9），本模块**不内联**
``obj.teacher_id != teacher.id``。``(teacher_id, name)`` 唯一性由**服务端显式查重**
保证（不依赖 DB UNIQUE——SQLite ``ALTER TABLE`` 静默忽略约束，见 ADR-0061 §R）。
"""

from __future__ import annotations

from uuid import UUID

from sqlmodel import Session, func, select

from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned
from app.db.models import Class, User


def _check_grade(grade: int) -> None:
    if not (1 <= grade <= 9):
        raise AppErrorException(
            ErrCode.VALIDATION, "年级必须在 1–9 之间"
        )


def _dup_name(session: Session, teacher_id: UUID, name: str, *, exclude_id: UUID | None = None) -> None:
    """同教师下重名显式查重；``exclude_id`` 用于改名时排除自身。"""
    stmt = select(Class).where(Class.teacher_id == teacher_id, Class.name == name)
    if exclude_id is not None:
        stmt = stmt.where(Class.id != exclude_id)
    if session.exec(stmt).first() is not None:
        raise AppErrorException(ErrCode.CLASS_NAME_TAKEN, "该教师下已存在同名班级")


def create_class(
    *, session: Session, teacher_id: UUID, name: str, grade: int
) -> Class:
    _check_grade(grade)
    _dup_name(session, teacher_id, name)
    klass = Class(teacher_id=teacher_id, name=name, grade=grade)
    session.add(klass)
    session.commit()
    session.refresh(klass)
    return klass


def _get_owned(session: Session, teacher_id: UUID, class_id: UUID) -> Class:
    return require_owned(
        session=session,
        owner_id=teacher_id,
        model=Class,
        obj_id=class_id,
        code=ErrCode.FORBIDDEN,
        message="班级不存在或不属于你的账号",
    )


def list_classes(*, session: Session, teacher_id: UUID) -> list[Class]:
    """本教师全部班级，附各班的在读学生数。"""
    classes = session.exec(
        select(Class).where(Class.teacher_id == teacher_id).order_by(Class.created_at)
    ).all()
    return classes


def student_counts(
    *, session: Session, teacher_id: UUID, class_ids: list[UUID]
) -> dict[UUID, int]:
    """按班级聚合在读学生数（role='student' 且已分班）。空列表返回空 dict。"""
    if not class_ids:
        return {}
    rows = session.exec(
        select(User.class_id, func.count())
        .where(
            User.teacher_id == teacher_id,
            User.role == "student",
            User.class_id.is_not(None),  # type: ignore[union-attr]
            User.class_id.in_(class_ids),  # type: ignore[union-attr]
        )
        .group_by(User.class_id)
    ).all()
    return {cid: count for cid, count in rows}


def update_class(
    *, session: Session, teacher_id: UUID, class_id: UUID, name: str | None, grade: int | None
) -> Class:
    klass = _get_owned(session, teacher_id, class_id)
    if grade is not None:
        _check_grade(grade)
        klass.grade = grade
    if name is not None and name != klass.name:
        _dup_name(session, teacher_id, name, exclude_id=class_id)
        klass.name = name
    session.add(klass)
    session.commit()
    session.refresh(klass)
    return klass


def delete_class(*, session: Session, teacher_id: UUID, class_id: UUID) -> None:
    """删除班级：班内学生 ``class_id`` 置空（降级未分班），账号与错题保留。"""
    klass = _get_owned(session, teacher_id, class_id)
    # 解除学生归属——不删学生、不删其错题数据。
    students = session.exec(
        select(User).where(User.teacher_id == teacher_id, User.class_id == class_id)
    ).all()
    for stu in students:
        stu.class_id = None
        session.add(stu)
    session.delete(klass)
    session.commit()
