"""Repository layer for the auth feature (user CRUD + password verification)."""

import uuid

from sqlmodel import Session, delete, func, select

from app.core.security import get_password_hash, verify_password
from app.db.models import (
    AnswerRecord,
    Checkin,
    TaskAssignment,
    User,
    WrongQuestion,
)
from app.features.auth.schemas import UserCreate


def create_user(
    *,
    session: Session,
    user_create: UserCreate,
    role: str,
    teacher_id: uuid.UUID | None = None,
) -> User:
    db_obj = User.model_validate(
        user_create,
        update={
            "hashed_password": get_password_hash(user_create.password),
            "role": role,
            "teacher_id": teacher_id,
        },
    )
    session.add(db_obj)
    session.commit()
    session.refresh(db_obj)
    return db_obj


def get_user_by_username(*, session: Session, username: str) -> User | None:
    from sqlmodel import select

    return session.exec(select(User).where(User.username == username)).first()


def get_user(*, session: Session, user_id: uuid.UUID) -> User | None:
    return session.get(User, user_id)


# 用户不存在时仍做一次假哈希校验，防止时序攻击
DUMMY_HASH = "$argon2id$v=19$m=65536,t=3,p=4$MjQyZWE1MzBjYjJlZTI0Yw$YTU4NGM5ZTZmYjE2NzZlZjY0ZWY3ZGRkY2U2OWFjNjk"


def authenticate(*, session: Session, username: str, password: str) -> User | None:
    db_user = get_user_by_username(session=session, username=username)
    if not db_user:
        verify_password(password, DUMMY_HASH)
        return None
    verified, updated_hash = verify_password(password, db_user.hashed_password)
    if not verified:
        return None
    if updated_hash:  # pwdlib 升级了哈希，回写
        db_user.hashed_password = updated_hash
        session.add(db_user)
        session.commit()
        session.refresh(db_user)
    return db_user


def list_students(*, session: Session, teacher_id: uuid.UUID) -> list[User]:
    from sqlmodel import select

    return list(session.exec(select(User).where(User.teacher_id == teacher_id)))


def update_user(
    *,
    session: Session,
    user: User,
    display_name: str | None = None,
    grade: int | None = None,
    interests: dict | None = None,
) -> User:
    """编辑学生资料（WF-5）：仅局部更新昵称/年级/兴趣；账号密码等字段不在此处变动。

    所有字段可选，仅传入非 None 的字段生效。
    """
    if display_name is not None:
        user.display_name = display_name
    if grade is not None:
        user.grade = grade
    if interests is not None:
        user.interests = interests
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def delete_student(*, session: Session, student: User) -> dict[str, int]:
    """硬删学生账号并级联清理其作答/打卡/错题/派发关系（单事务，ADR-0068）。

    先数后删，回传各表清理行数让教师确认没有误删（验收要求）。所有删除在同一
    ``commit`` 内完成，任一步失败整体回滚（原子级联）。

    ⚠️ 范围：仅清理与「学生作答/打卡/错题/派发」直接相关的四张表 + 账号本身。
    ``TutorLog`` / ``Conversation`` 等伴学日志不在此级联（属日志且非 spec 要求），
    避免误删教师侧数据；其 ``student_id`` 为可空引用，留痕不影响其他功能。
    """

    def _count(model: type) -> int:
        return (
            session.scalar(
                select(func.count())
                .select_from(model)
                .where(model.student_id == student.id)
            )
            or 0
        )

    counts = {
        "answer_records": _count(AnswerRecord),
        "checkins": _count(Checkin),
        "wrong_questions": _count(WrongQuestion),
        "task_assignments": _count(TaskAssignment),
    }
    # 子表先删，账号最后删；单事务提交保证原子。
    session.exec(delete(AnswerRecord).where(AnswerRecord.student_id == student.id))
    session.exec(delete(Checkin).where(Checkin.student_id == student.id))
    session.exec(delete(WrongQuestion).where(WrongQuestion.student_id == student.id))
    session.exec(delete(TaskAssignment).where(TaskAssignment.student_id == student.id))
    session.delete(student)
    session.commit()
    return counts
