import uuid
from datetime import date, timedelta

from sqlmodel import Session, func, select

from app.core.security import get_password_hash, verify_password
from app.models import (
    AnswerRecord,
    Checkin,
    Question,
    Task,
    User,
    UserCreate,
    WrongQuestion,
)


# ───────── 用户 ─────────
def create_user(
    *,
    session: Session,
    user_create: UserCreate,
    role: str,
    parent_id: uuid.UUID | None = None,
) -> User:
    db_obj = User.model_validate(
        user_create,
        update={
            "hashed_password": get_password_hash(user_create.password),
            "role": role,
            "parent_id": parent_id,
        },
    )
    session.add(db_obj)
    session.commit()
    session.refresh(db_obj)
    return db_obj


def get_user_by_username(*, session: Session, username: str) -> User | None:
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


def list_children(*, session: Session, parent_id: uuid.UUID) -> list[User]:
    return list(session.exec(select(User).where(User.parent_id == parent_id)))


# ───────── 任务 / 题目 ─────────
def create_task(*, session: Session, **kwargs) -> Task:
    task = Task(**kwargs)
    session.add(task)
    session.commit()
    session.refresh(task)
    return task


def add_questions(*, session: Session, questions: list[Question]) -> None:
    session.add_all(questions)
    session.commit()


def get_task(*, session: Session, task_id: uuid.UUID) -> Task | None:
    return session.get(Task, task_id)


def get_questions(*, session: Session, task_id: uuid.UUID) -> list[Question]:
    return list(session.exec(select(Question).where(Question.task_id == task_id)))


def get_child_tasks_today(*, session: Session, child_id: uuid.UUID) -> list[Task]:
    today = date.today()
    return list(
        session.exec(
            select(Task).where(
                Task.child_id == child_id,
                func.date(Task.created_at) == today,
            )
        )
    )


# ───────── 作答 / 打卡 / 进度 ─────────
def create_answer_record(
    *,
    session: Session,
    question_id: uuid.UUID,
    child_id: uuid.UUID,
    student_answer: str,
    correct: bool,
    score: float,
) -> AnswerRecord:
    rec = AnswerRecord(
        question_id=question_id,
        child_id=child_id,
        student_answer=student_answer,
        correct=correct,
        score=score,
    )
    session.add(rec)
    session.commit()
    session.refresh(rec)
    return rec


def create_checkin(
    *,
    session: Session,
    child_id: uuid.UUID,
    task_id: uuid.UUID,
    checkin_date: date,
) -> Checkin:
    existing = session.exec(
        select(Checkin).where(
            Checkin.child_id == child_id,
            Checkin.task_id == task_id,
            Checkin.checkin_date == checkin_date,
        )
    ).first()
    if existing:
        return existing
    c = Checkin(child_id=child_id, task_id=task_id, checkin_date=checkin_date)
    session.add(c)
    session.commit()
    session.refresh(c)
    return c


def _compute_streak(checkin_dates: list[date]) -> int:
    days = set(checkin_dates)
    if not days:
        return 0
    streak = 0
    d = date.today()
    while d in days:
        streak += 1
        d -= timedelta(days=1)
    return streak


def get_progress(*, session: Session, child_id: uuid.UUID) -> tuple[int, int, int, int]:
    total = (
        session.scalar(
            select(func.count(AnswerRecord.id)).where(
                AnswerRecord.child_id == child_id
            )
        )
        or 0
    )
    correct = (
        session.scalar(
            select(func.count(AnswerRecord.id)).where(
                AnswerRecord.child_id == child_id,
                AnswerRecord.correct == True,  # noqa: E712
            )
        )
        or 0
    )
    checkin_dates = list(
        session.exec(select(Checkin.checkin_date).where(Checkin.child_id == child_id)).all()
    )
    checkin_days = len(set(checkin_dates))
    streak = _compute_streak(checkin_dates)
    return total, correct, checkin_days, streak


# ───────── 错题集 ─────────
def upsert_wrong_question(
    *,
    session: Session,
    question_id: uuid.UUID,
    child_id: uuid.UUID,
) -> WrongQuestion:
    """答错时归集错题：已存在则次数 +1，不建多条（故事 13）。"""
    existing = session.exec(
        select(WrongQuestion).where(
            WrongQuestion.child_id == child_id,
            WrongQuestion.question_id == question_id,
        )
    ).first()
    if existing:
        existing.wrong_count += 1
        session.add(existing)
        session.commit()
        session.refresh(existing)
        return existing
    wq = WrongQuestion(child_id=child_id, question_id=question_id)
    session.add(wq)
    session.commit()
    session.refresh(wq)
    return wq


def list_wrong_questions(
    *, session: Session, child_id: uuid.UUID
) -> list[tuple[WrongQuestion, Question]]:
    """错题列表：join Question 取完整题目，按首次错时间倒序。"""
    rows = session.exec(
        select(WrongQuestion, Question)
        .join(Question, Question.id == WrongQuestion.question_id)
        .where(WrongQuestion.child_id == child_id)
        .order_by(WrongQuestion.first_wrong_at.desc())
    ).all()
    return list(rows)
