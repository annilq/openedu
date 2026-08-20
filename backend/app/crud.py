import math
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, func, select, update

from app.core.security import get_password_hash, verify_password
from app.domain.mastery import RECENT_WINDOW
from app.domain.review_scheduler import (
    advance_stage,
    due_after_correct,
    due_after_wrong,
)
from app.models import (
    AnswerRecord,
    Checkin,
    Question,
    Task,
    TutorLog,
    TutorQuota,
    TutorUsage,
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
    today = datetime.now(UTC).date()
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
    source: str = "practice",
) -> AnswerRecord:
    rec = AnswerRecord(
        question_id=question_id,
        child_id=child_id,
        student_answer=student_answer,
        correct=correct,
        score=score,
        source=source,
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


# ───────── 错题集 / 遗忘曲线复习 ─────────
def upsert_wrong_question(
    *,
    session: Session,
    question_id: uuid.UUID,
    child_id: uuid.UUID,
) -> WrongQuestion:
    """答错归集错题（故事 13）：已存在则次数 +1 不建多条。

    每次答错都重置遗忘曲线计时器（故事 17）：review_stage=0、last_wrong_at=now、
    due_at=now+1d，保证「重复错 = 从头再来」。
    """
    now = datetime.now(UTC)
    existing = session.exec(
        select(WrongQuestion).where(
            WrongQuestion.child_id == child_id,
            WrongQuestion.question_id == question_id,
        )
    ).first()
    if existing:
        existing.wrong_count += 1
        existing.review_stage = 0
        existing.last_wrong_at = now
        existing.due_at = due_after_wrong(now)
        session.add(existing)
        session.commit()
        session.refresh(existing)
        return existing
    wq = WrongQuestion(
        child_id=child_id,
        question_id=question_id,
        wrong_count=1,
        review_stage=0,
        last_wrong_at=now,
        due_at=due_after_wrong(now),
    )
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


def list_due_wrong_questions(
    *, session: Session, child_id: uuid.UUID
) -> list[tuple[WrongQuestion, Question]]:
    """到期错题（due_at <= now）：遗忘曲线到点后纳入待复习队列（故事 14）。"""
    rows = session.exec(
        select(WrongQuestion, Question)
        .join(Question, Question.id == WrongQuestion.question_id)
        .where(
            WrongQuestion.child_id == child_id,
            WrongQuestion.due_at <= datetime.now(UTC),
        )
        .order_by(WrongQuestion.due_at.asc())
    ).all()
    return list(rows)


def mark_review_result(
    *,
    session: Session,
    wrong_question_id: uuid.UUID,
    correct: bool,
) -> WrongQuestion | None:
    """更新复习作答后的调度状态。

    - 答对：推进阶段（1→2→4→7→15 天）；末位阶段答对视为掌握，从错题集移除（返回 None）。
    - 答错：重置为首档 1 天（故事 17），wrong_count +1。
    """
    wq = session.get(WrongQuestion, wrong_question_id)
    if wq is None:
        # 并发下末位答对已毕业删除，或 id 无效：调用方按「不存在」处理（路由转 404）
        return None
    now = datetime.now(UTC)
    if correct:
        new_stage = advance_stage(wq.review_stage)
        if new_stage is None:
            session.delete(wq)
            session.commit()
            return None
        wq.review_stage = new_stage
        wq.due_at = due_after_correct(now, new_stage)
    else:
        wq.review_stage = 0
        wq.last_wrong_at = now
        wq.due_at = due_after_wrong(now)
        wq.wrong_count += 1
    session.add(wq)
    session.commit()
    session.refresh(wq)
    return wq


# ───────── 知识点掌握度看板（T06，F-204） ─────────
@dataclass
class KnowledgePointAgg:
    """单个知识点的掌握度原始聚合（喂给 domain/mastery 纯函数）。"""

    knowledge_point: str
    subject: str
    grade: int
    total_answers: int = 0
    correct_answers: int = 0
    recent_total: int = 0
    recent_correct: int = 0
    active_wrong: int = 0
    max_review_stage: int = 0


def get_knowledge_point_mastery(
    *, session: Session, child_id: uuid.UUID
) -> list[KnowledgePointAgg]:
    """聚合某娃娃的按知识点掌握度输入数据。

    - 作答记录按 created_at 倒序取最近 RECENT_WINDOW 次作为「近期表现」。
    - 活跃错题（未毕业）计入 active_wrong 与最高复习阶段 max_review_stage。
    """
    groups: dict[str, KnowledgePointAgg] = {}

    records = session.exec(
        select(AnswerRecord, Question)
        .join(Question, Question.id == AnswerRecord.question_id)
        .where(AnswerRecord.child_id == child_id)
        .order_by(AnswerRecord.created_at.desc(), AnswerRecord.id.desc())
    ).all()
    for rec, q in records:
        agg = groups.get(q.knowledge_point)
        if agg is None:
            agg = KnowledgePointAgg(
                knowledge_point=q.knowledge_point,
                subject=q.subject,
                grade=q.grade,
            )
            groups[q.knowledge_point] = agg
        agg.total_answers += 1
        agg.correct_answers += 1 if rec.correct else 0
        if agg.recent_total < RECENT_WINDOW:
            agg.recent_total += 1
            agg.recent_correct += 1 if rec.correct else 0

    wrong_rows = session.exec(
        select(WrongQuestion, Question)
        .join(Question, Question.id == WrongQuestion.question_id)
        .where(WrongQuestion.child_id == child_id)
    ).all()
    for wq, q in wrong_rows:
        agg = groups.get(q.knowledge_point)
        if agg is not None:  # 答错必写过作答记录，理论恒存在
            agg.active_wrong += 1
            agg.max_review_stage = max(agg.max_review_stage, wq.review_stage)

    return list(groups.values())


# ───────── AI 伴学答疑日志（F-305） ─────────
def create_tutor_log(
    *,
    session: Session,
    child_id: uuid.UUID,
    grade: int,
    subject: str,
    knowledge_point: str,
    question: str,
    answer: str,
    input_safe: bool,
    output_safe: bool,
    blocked: bool,
) -> TutorLog:
    log = TutorLog(
        child_id=child_id,
        grade=grade,
        subject=subject,
        knowledge_point=knowledge_point,
        question=question,
        answer=answer,
        input_safe=input_safe,
        output_safe=output_safe,
        blocked=blocked,
    )
    session.add(log)
    session.commit()
    session.refresh(log)
    return log


def count_tutor_today(*, session: Session, child_id: uuid.UUID) -> int:
    """当日已使用的 AI 答疑次数（F-304 每日上限判定）。"""
    today = datetime.now(UTC).date()
    return session.exec(
        select(func.count(TutorLog.id)).where(
            TutorLog.child_id == child_id,
            func.date(TutorLog.created_at) == today.isoformat(),
        )
    ).one()


def list_tutor_logs(
    *, session: Session, child_id: uuid.UUID, limit: int = 200
) -> list[TutorLog]:
    """按时间倒序返回某娃娃的 AI 答疑日志（家长端查看）。"""
    return session.exec(
        select(TutorLog)
        .where(TutorLog.child_id == child_id)
        .order_by(TutorLog.created_at.desc())
        .limit(limit)
    ).all()


# ───────── AI 使用管控（T10，故事 23/26） ─────────
def get_tutor_quota(*, session: Session, child_id: uuid.UUID) -> TutorQuota | None:
    """读取某娃娃的 AI 使用管控配置（未配置返回 None，走全局默认）。"""
    return session.exec(
        select(TutorQuota).where(TutorQuota.child_id == child_id)
    ).first()


def upsert_tutor_quota(
    *,
    session: Session,
    child_id: uuid.UUID,
    daily_ask_limit: int | None,
    daily_minutes_limit: int | None,
    allowed_subjects: list[str] | None,
) -> TutorQuota:
    """写入/更新某娃娃的管控配置（每娃一条，整体覆盖）。"""
    quota = get_tutor_quota(session=session, child_id=child_id)
    if quota is None:
        quota = TutorQuota(child_id=child_id)
    quota.daily_ask_limit = daily_ask_limit
    quota.daily_minutes_limit = daily_minutes_limit
    quota.allowed_subjects = allowed_subjects
    quota.updated_at = datetime.now(UTC)
    session.add(quota)
    session.commit()
    session.refresh(quota)
    return quota


def _today_usage(
    session: Session, child_id: uuid.UUID, today: date
) -> TutorUsage | None:
    return session.exec(
        select(TutorUsage).where(
            TutorUsage.child_id == child_id,
            TutorUsage.usage_date == today,
        )
    ).first()


def get_tutor_usage_today(
    *, session: Session, child_id: uuid.UUID
) -> TutorUsage | None:
    """只读取当日用量行（GET 接口用，无写副作用）；无则 None。"""
    return _today_usage(session, child_id, datetime.now(UTC).date())


def get_or_create_tutor_usage(
    *, session: Session, child_id: uuid.UUID
) -> TutorUsage:
    """取当日用量行（不存在则建，used_seconds=0）。

    并发首问时另一请求可能已抢先建行：捕获唯一约束冲突回滚后重查，
    而不是让请求 500。
    """
    today = datetime.now(UTC).date()
    usage = _today_usage(session, child_id, today)
    if usage is None:
        usage = TutorUsage(child_id=child_id, usage_date=today, used_seconds=0)
        session.add(usage)
        try:
            session.commit()
        except IntegrityError:
            session.rollback()
            usage = _today_usage(session, child_id, today)
            if usage is None:  # 理论不可达：冲突后行必存在
                raise
        else:
            session.refresh(usage)
    return usage


def add_tutor_usage(
    *, session: Session, child_id: uuid.UUID, seconds: float
) -> None:
    """答疑完成后累计当日耗时（秒，向上取整避免瞬时调用永远记 0）。

    用 SQL 原子自增（used_seconds = used_seconds + n），避免并发下读-改-写丢更新。
    """
    today = datetime.now(UTC).date()
    get_or_create_tutor_usage(session=session, child_id=child_id)
    session.execute(
        update(TutorUsage)
        .where(
            TutorUsage.child_id == child_id,
            TutorUsage.usage_date == today,
        )
        .values(used_seconds=TutorUsage.used_seconds + max(0, math.ceil(seconds)))
    )
    session.commit()
