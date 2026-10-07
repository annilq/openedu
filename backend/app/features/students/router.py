from uuid import UUID

from fastapi import APIRouter, HTTPException, status

from app.core.deps import CurrentTeacher, SessionDep
from app.core.errors import ErrCode
from app.core.guard import require_owned_student
from app.features.auth.repository import (
    create_user,
    delete_student,
    get_user_by_username,
    list_students,
    update_user,
)
from app.features.auth.schemas import (
    DeletedStudentResp,
    UserCreate,
    UserPublic,
    UsersPublic,
    UserUpdate,
)

router = APIRouter(prefix="/students", tags=["students"])


@router.post("", response_model=UserPublic, status_code=status.HTTP_201_CREATED)
def create_student(
    *, session: SessionDep, teacher: CurrentTeacher, student_in: UserCreate
) -> UserPublic:
    if get_user_by_username(session=session, username=student_in.username):
        raise HTTPException(status_code=400, detail="Username already registered")
    student = create_user(
        session=session,
        user_create=student_in,
        role="student",
        teacher_id=teacher.id,
    )
    return student


@router.put("/{student_id}", response_model=UserPublic)
def update_student(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    student_id: UUID,
    payload: UserUpdate,
) -> UserPublic:
    """编辑学生资料（WF-5）：仅昵称/年级/兴趣可改，账号密码锁定不编辑。

    仅传入非 None 的字段生效；目标学生须属于当前教师。
    """
    student = require_owned_student(
        session=session,
        owner_id=teacher.id,
        student_id=student_id,
        code=ErrCode.NOT_FOUND,
        message="学生不存在或不属于你的账号",
    )
    if student.role != "student":
        raise HTTPException(status_code=400, detail="仅可编辑学生账号")
    # 局部更新：忽略未传入（None）的字段
    patch = payload.model_dump(exclude_unset=True)
    if not patch:
        return student
    updated = update_user(
        session=session,
        user=student,
        display_name=payload.display_name,
        grade=payload.grade,
        interests=payload.interests,
    )
    return updated


@router.get("", response_model=UsersPublic)
def get_students(*, session: SessionDep, teacher: CurrentTeacher) -> UsersPublic:
    students = list_students(session=session, teacher_id=teacher.id)
    return UsersPublic(data=students, count=len(students))


@router.delete("/{student_id}", response_model=DeletedStudentResp)
def delete_student_endpoint(
    *, session: SessionDep, teacher: CurrentTeacher, student_id: UUID
) -> DeletedStudentResp:
    """删除学生账号（硬删 + 级联清理作答/打卡/错题/派发关系，单事务，ADR-0068）。

    回传各表清理行数供教师确认没有误删；别教师的学生 / 不存在返回 403。
    """
    student = require_owned_student(
        session=session,
        owner_id=teacher.id,
        student_id=student_id,
        code=ErrCode.FORBIDDEN,
        message="学生不存在或不属于你的账号",
    )
    if student.role != "student":
        raise HTTPException(status_code=400, detail="仅可删除学生账号")
    counts = delete_student(session=session, student=student)
    return DeletedStudentResp(student_id=student_id, **counts)
