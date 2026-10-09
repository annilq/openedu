from uuid import UUID

from fastapi import APIRouter, File, HTTPException, Query, Response, UploadFile, status

from app.core.config import settings
from app.core.deps import CurrentTeacher, SessionDep
from app.core.errors import ErrCode
from app.core.guard import require_owned_student
from app.db.models import Question, User, WrongQuestion
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
from app.features.students.schemas import (
    StudentBatchReassignReq,
    StudentBatchReassignResp,
    StudentImportResult,
)
from app.features.students.service import (
    batch_reassign_class,
    export_students_import_template,
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


@router.get("/import-template")
def download_student_import_template(
    *, session: SessionDep, teacher: CurrentTeacher
) -> Response:
    """下载学生导入模板 xlsx（方案A）：表头为「姓名 / 学号」，供教师先下载规范模板再填写上传。

    表头与 ``POST /students/import`` 的解析口径严格一致（``service._NAME_HEADERS`` /
    ``_NO_HEADERS`` 的中文别名），教师按模板填写即可避免列序错位 / 缺列失败。
    """
    data = export_students_import_template()
    return Response(
        content=data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": "attachment; filename=student_import_template.xlsx"
        },
    )


@router.put("/{student_id}", response_model=UserPublic)
def update_student(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    student_id: UUID,
    payload: UserUpdate,
) -> UserPublic:
    """编辑学生资料（WF-5）：仅昵称/年级可改，账号密码锁定不编辑。

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


@router.get("/wrong-question-counts", response_model=dict[str, int])
def get_students_wrong_question_counts(
    *, session: SessionDep, teacher: CurrentTeacher
) -> dict[str, int]:
    """各学生的活跃（未毕业）错题数，供学生管理页每行展示（ADR-0068 §2.3 / ticket 02）。

    按当前教师的归属范围聚合：JOIN ``user`` 取 ``teacher_id``，再 JOIN ``question``
    只数 ``graduated_at`` 为空 **且源题目仍存在** 的活跃错题——与「错题本」详情页
    （``GET /students/{id}/wrong-questions?scope=active`` 的 ``WrongQuestion JOIN
    Question``）口径一致，避免列表徽标出现「数得到、点进去却看不到」的孤儿错题。
    返回 ``{student_id: count}``，无错题的学生不出现在结果里。
    """
    from sqlmodel import func, select

    rows = session.exec(
        select(WrongQuestion.student_id, func.count())
        .join(User, WrongQuestion.student_id == User.id)
        .join(Question, WrongQuestion.question_id == Question.id)
        .where(User.teacher_id == teacher.id, WrongQuestion.graduated_at.is_(None))
        .group_by(WrongQuestion.student_id)
    ).all()
    return {str(sid): cnt for sid, cnt in rows}


@router.post("/batch-reassign", response_model=StudentBatchReassignResp)
def batch_reassign_students(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    req: StudentBatchReassignReq,
) -> StudentBatchReassignResp:
    """批量移入/移出班级（ticket 03）。

    ``class_id=None`` 表示移出班级（归入未分班）；否则移入该班级。整批单事务：
    任一学生或班级越权即整体失败回滚。返回实际改动的行数（已在目标班的跳过不计）。
    """
    updated = batch_reassign_class(
        session=session, teacher_id=teacher.id, req=req
    )
    return StudentBatchReassignResp(updated=updated, class_id=req.class_id)


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
