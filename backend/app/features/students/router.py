from uuid import UUID

from fastapi import APIRouter, File, HTTPException, Query, Response, UploadFile, status

from app.core.config import settings
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
from app.features.students.schemas import StudentImportResult
from app.features.students.service import (
    export_students_xlsx,
    import_students_from_xlsx,
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


@router.post("/import", response_model=StudentImportResult)
async def import_students(
    *, session: SessionDep, teacher: CurrentTeacher, file: UploadFile = File(...)
) -> StudentImportResult:
    """批量导入学生（ADR-0068 §2.2）：上传 xlsx 花名册，username=学号、初始密码=配置值。

    - 文件大小超限 → 413；缺必要列 / 行数超限 / 空文件 → 400。
    - 逐行缺列或学号冲突 → 落 ``skipped`` 并回传行号，整体仍 200（见 ``StudentImportResult``）。
    """
    data = await file.read()
    if len(data) > settings.STUDENT_IMPORT_MAX_BYTES:
            raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=f"文件过大，上限 {settings.STUDENT_IMPORT_MAX_BYTES} 字节",
        )
    try:
        return import_students_from_xlsx(
            session=session, teacher_id=teacher.id, data=data
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        )


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
def get_students(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    class_id: UUID | None = Query(default=None, description="按班级筛选；不传=全部"),
    keyword: str | None = Query(default=None, description="按姓名或学号模糊搜索"),
) -> UsersPublic:
    students = list_students(
        session=session,
        teacher_id=teacher.id,
        class_id=class_id,
        keyword=keyword,
    )
    return UsersPublic(data=students, count=len(students))


@router.get("/export")
def export_students(*, session: SessionDep, teacher: CurrentTeacher) -> Response:
    """导出账号表 xlsx（班级 / 姓名 / 学号 / 初始密码），供教师打印或分发给学生和家长。

    未分班学生班级列标记「未分班」；初始密码与导入时设定的配置值一致（ADR-0068 §2.2）。
    与导入共用 openpyxl，无第二套依赖。
    """
    data = export_students_xlsx(session=session, teacher_id=teacher.id)
    return Response(
        content=data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": "attachment; filename=students.xlsx"},
    )


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
