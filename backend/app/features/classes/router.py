"""班级路由（ADR-0068）。

所有端点 ``CurrentTeacher``；归属校验下沉到 service（``require_owned``），路由只做
「接参数 → 调 service → 包响应」。删班仅置空学生 ``class_id``，不删学生或其错题。
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, status

from app.core.deps import CurrentTeacher, SessionDep
from app.features.classes.schemas import ClassCreate, ClassResp, ClassUpdate
from app.features.classes.service import (
    create_class,
    delete_class,
    list_classes,
    student_counts,
    update_class,
)

router = APIRouter(prefix="/classes", tags=["classes"])


@router.post("", response_model=ClassResp, status_code=status.HTTP_201_CREATED)
def create_class_endpoint(
    *, session: SessionDep, teacher: CurrentTeacher, req: ClassCreate
) -> ClassResp:
    klass = create_class(
        session=session, teacher_id=teacher.id, name=req.name, grade=req.grade
    )
    return ClassResp(
        id=klass.id,
        name=klass.name,
        grade=klass.grade,
        created_at=klass.created_at,
    )


@router.get("", response_model=list[ClassResp])
def list_classes_endpoint(
    *, session: SessionDep, teacher: CurrentTeacher
) -> list[ClassResp]:
    classes = list_classes(session=session, teacher_id=teacher.id)
    counts = student_counts(
        session=session, teacher_id=teacher.id, class_ids=[c.id for c in classes]
    )
    return [
        ClassResp(
            id=c.id,
            name=c.name,
            grade=c.grade,
            student_count=counts.get(c.id, 0),
            created_at=c.created_at,
        )
        for c in classes
    ]


@router.patch("/{class_id}", response_model=ClassResp)
def update_class_endpoint(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    class_id: UUID,
    req: ClassUpdate,
) -> ClassResp:
    klass = update_class(
        session=session,
        teacher_id=teacher.id,
        class_id=class_id,
        name=req.name,
        grade=req.grade,
    )
    return ClassResp(
        id=klass.id,
        name=klass.name,
        grade=klass.grade,
        created_at=klass.created_at,
    )


@router.delete("/{class_id}")
def delete_class_endpoint(
    *, session: SessionDep, teacher: CurrentTeacher, class_id: UUID
) -> dict:
    delete_class(session=session, teacher_id=teacher.id, class_id=class_id)
    return {"deleted": True}
