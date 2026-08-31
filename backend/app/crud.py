import math
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, func, select, update

from app.core.crypto import encrypt
from app.core.errors import AppErrorException, ErrCode
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
    ModelConfig,
    Question,
    Task,
    TaskQuestion,
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


def update_user(
    *,
    session: Session,
    user: User,
    display_name: str | None = None,
    grade: int | None = None,
    interests: dict | None = None,
) -> User:
    """编辑娃娃资料（WF-5）：仅局部更新昵称/年级/兴趣；账号密码等字段不在此处变动。

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


# ───────── 任务 / 题目 / 题库快照（ADR-0004） ─────────
def create_task(*, session: Session, **kwargs) -> Task:
    task = Task(**kwargs)
    session.add(task)
    session.commit()
    session.refresh(task)
    return task


def get_task(*, session: Session, task_id: uuid.UUID) -> Task | None:
    return session.get(Task, task_id)


def get_task_questions(*, session: Session, task_id: uuid.UUID) -> list[TaskQuestion]:
    """查某 Task 的派发快照题（草稿态 = 草稿项，assigned 后 = 只读快照）。"""
    return list(
        session.exec(
            select(TaskQuestion)
            .where(TaskQuestion.task_id == task_id)
            .order_by(TaskQuestion.created_at, TaskQuestion.id)
        )
    )


def get_task_question(*, session: Session, tq_id: uuid.UUID) -> TaskQuestion | None:
    return session.get(TaskQuestion, tq_id)


def add_question_to_bank(*, session: Session, question: Question) -> Question:
    """题入题库层（Question 表独立实体，不绑 task_id，ADR-0004 D2）。"""
    session.add(question)
    session.commit()
    session.refresh(question)
    return question


def batch_generate_task(
    *,
    session: Session,
    parent_id: uuid.UUID,
    title: str,
    child_id: uuid.UUID | None,
    specs_dicts: list[dict],
    task_questions: list[TaskQuestion],
    focus_interest: list[str] | None = None,
) -> Task:
    """批量建草稿 Task + 挂草稿项（R-Q1=c：不预写 Question，只写 TaskQuestion）。

    - `specs_dicts`：原始生成规格的 list[dict]，持久化到 Task.specs 以便整卷重生成。
    - `task_questions`：路由层已用 QuestionGenerator 生成的草稿项（未写 Question）。
      路由层不 commit 直接传进来，避免和 Task 事务拆分。
    - `focus_interest`：兴趣题模式聚焦主题（WF-4），整卷共享，随草稿持久化。
    """
    task = Task(
        title=title,
        status="draft",
        parent_id=parent_id,
        child_id=child_id,
        specs=specs_dicts or None,
        focus_interest=focus_interest,
    )
    session.add(task)
    session.flush()  # 拿到 task.id

    for tq in task_questions:
        tq.task_id = task.id
    session.add_all(task_questions)
    session.commit()
    session.refresh(task)
    return task


def update_task_question(
    *,
    session: Session,
    tq_id: uuid.UUID,
    edits: dict,
) -> TaskQuestion | None:
    """编辑草稿快照题（仅 draft 态，路由层校验；qtype 不在可改字段内）。"""
    tq = session.get(TaskQuestion, tq_id)
    if tq is None:
        return None
    for k, v in edits.items():
        if v is not None:
            setattr(tq, k, v)
    session.add(tq)
    session.commit()
    session.refresh(tq)
    return tq


# confirm_task sentinel：None 语义冲突时用对象标记。task_id 不是自定义对象，安全。
class _Sentinel:
    def __init__(self, tag: str) -> None:
        self.tag = tag


_SENTINEL_PROMOTE_REQUIRED = _Sentinel("promote_required")
_SENTINEL_NO_QUESTIONS = _Sentinel("no_questions")


def confirm_task(*, session: Session, task_id: uuid.UUID) -> Task | None:
    """draft → ready：家长确认锁定题集（CONTEXT 草稿/锁定/派发）。

    R-Q1=c 锁定前校验：所有草稿项 question_id 非空（都已加入题库）。
    不通过时返回对应 _SENTINEL 对象（路由层识别后抛精确错误码）。
    """
    task = session.get(Task, task_id)
    if task is None or task.status != "draft":
        return None
    tqs = get_task_questions(session=session, task_id=task.id)
    if not tqs:
        return _SENTINEL_NO_QUESTIONS
    if any(tq.question_id is None for tq in tqs):
        return _SENTINEL_PROMOTE_REQUIRED
    task.status = "ready"
    session.add(task)
    session.commit()
    session.refresh(task)
    return task


def promote_task_question(
    *, session: Session, tq_id: uuid.UUID
) -> TaskQuestion | None:
    """草稿题加入题库（R-Q1=c：把 TaskQuestion 字段拷贝写 Question，回填 question_id）。

    已入题库则直接返回（幂等）。返回 None = TaskQuestion 不存在。
    """
    tq = session.get(TaskQuestion, tq_id)
    if tq is None:
        return None
    if tq.question_id is not None:
        # 已入题库的如果 Question 行仍在则直接返回；否则补写（异常情形）。
        if session.get(Question, tq.question_id) is not None:
            return tq
    q = Question(
        parent_id=session.get(Task, tq.task_id).parent_id,  # owner 隔离（闭环）
        subject=tq.subject,
        grade=tq.grade,
        knowledge_point=tq.knowledge_point,
        qtype=tq.qtype,
        stem=tq.stem,
        options=tq.options,
        answer=tq.answer,
        explanation=tq.explanation,
        difficulty=tq.difficulty,
    )
    session.add(q)
    session.flush()
    tq.question_id = q.id
    session.add(tq)
    session.commit()
    session.refresh(tq)
    return tq


def remove_task_question(
    *, session: Session, tq_id: uuid.UUID
) -> bool:
    """删除草稿项。R-Q5=b：同时物理删除同 Question（若 question_id 非空）。

    返回 False 表示 TaskQuestion 不存在，True 为删除成功。
    """
    tq = session.get(TaskQuestion, tq_id)
    if tq is None:
        return False
    qid = tq.question_id
    session.delete(tq)
    session.flush()
    if qid is not None:
        # 级联安全（闭环）：仅当源题不再被任何任务引用才物理删除，
        # 否则只脱离本草稿副本，避免误删被其他任务共享的题库题。
        remaining = session.exec(
            select(TaskQuestion).where(TaskQuestion.question_id == qid)
        ).all()
        if len(remaining) <= 1:
            q = session.get(Question, qid)
            if q is not None:
                session.delete(q)
    session.commit()
    return True


def regenerate_one_task_question(
    *, session: Session, tq_id: uuid.UUID, gen_question: Question
) -> TaskQuestion | None:
    """单题重生成：用 QuestionGenerator 生成的新字段覆盖当前 TaskQuestion。

    - 原 question_id 对应的 Question 同步删（R-Q5=b 级联）；
    - 新题未入题库（Question 只在生成器返回里保存为「临时对象」，不写 Question 表），
      家长后续还需要点「加入题库」才真正入 Question 表。
    """
    tq = session.get(TaskQuestion, tq_id)
    if tq is None:
        return None
    old_qid = tq.question_id
    # 用新题字段覆盖（保留 subject/grade/knowledge_point/qtype 与生成器一致即可）
    tq.subject = gen_question.subject
    tq.grade = gen_question.grade
    tq.knowledge_point = gen_question.knowledge_point
    tq.qtype = gen_question.qtype
    tq.stem = gen_question.stem
    tq.options = gen_question.options
    tq.answer = gen_question.answer
    tq.explanation = gen_question.explanation
    tq.difficulty = gen_question.difficulty
    tq.question_id = None  # 新题未入库
    session.add(tq)
    session.flush()
    if old_qid is not None:
        # 级联安全（闭环）：仅当源题不再被任何任务引用才物理删除。
        remaining = session.exec(
            select(TaskQuestion).where(TaskQuestion.question_id == old_qid)
        ).all()
        if len(remaining) <= 1:
            q = session.get(Question, old_qid)
            if q is not None:
                session.delete(q)
    session.commit()
    session.refresh(tq)
    return tq


def regenerate_all_task_questions(
    *,
    session: Session,
    task_id: uuid.UUID,
    new_task_questions: list[TaskQuestion],
    specs_dicts: list[dict] | None = None,
) -> Task | None:
    """整卷重生成（R-Q2=c）：按原 specs 重跑，全量替换草稿项。

    同时清理当前草稿所有已入库的 Question（R-Q5=b 级联）。
    若传入 specs_dicts 则更新 Task.specs（家长在 UI 上调整了规格）。
    """
    task = session.get(Task, task_id)
    if task is None or task.status != "draft":
        return None
    old = get_task_questions(session=session, task_id=task.id)
    old_qids = [tq.question_id for tq in old if tq.question_id is not None]
    # 删旧草稿项（物理）
    for tq in old:
        session.delete(tq)
    # 删旧 Question 行
    for qid in old_qids:
        q = session.get(Question, qid)
        if q is not None:
            session.delete(q)
    session.flush()
    for tq in new_task_questions:
        tq.task_id = task.id
    session.add_all(new_task_questions)
    if specs_dicts is not None:
        task.specs = specs_dicts or None
    session.add(task)
    session.commit()
    session.refresh(task)
    return task


# ───────── 题库复用闭环（GET /questions / POST /tasks/from-bank 等） ─────────
def list_bank_questions(
    *,
    session: Session,
    parent_id: uuid.UUID,
    subject: str | None = None,
    grade: int | None = None,
    knowledge_point: str | None = None,
    qtype: str | None = None,
    keyword: str | None = None,
    page: int = 1,
    page_size: int = 20,
) -> tuple[list[Question], int, dict[uuid.UUID, int]]:
    """题库浏览（家长作用域）：过滤分页 + 每题被多少 Task 引用的复用度。

    返回 (items, total, usage)，usage 为 question_id -> 引用次数 映射。
    """
    stmt = select(Question).where(Question.parent_id == parent_id)
    if subject:
        stmt = stmt.where(Question.subject == subject)
    if grade is not None:
        stmt = stmt.where(Question.grade == grade)
    if knowledge_point:
        stmt = stmt.where(Question.knowledge_point == knowledge_point)
    if qtype:
        stmt = stmt.where(Question.qtype == qtype)
    if keyword:
        like = f"%{keyword}%"
        stmt = stmt.where(
            (Question.stem.ilike(like)) | (Question.knowledge_point.ilike(like))
        )
    total = len(session.exec(stmt).all())
    items = session.exec(
        stmt.order_by(Question.created_at.desc())
        .offset((max(1, page) - 1) * page_size)
        .limit(page_size)
    ).all()
    ids = [q.id for q in items]
    usage: dict[uuid.UUID, int] = {}
    if ids:
        rows = session.exec(
            select(TaskQuestion.question_id, func.count())
            .where(TaskQuestion.question_id.in_(ids))
            .group_by(TaskQuestion.question_id)
        ).all()
        usage = {qid: c for qid, c in rows}
    return items, total, usage


def create_task_from_bank(
    *,
    session: Session,
    parent_id: uuid.UUID,
    title: str,
    child_id: uuid.UUID | None = None,
    question_ids: list[uuid.UUID],
) -> Task:
    """选项 A：从题库新建任务（draft）。

    深拷贝选中题为 TaskQuestion 并回填 question_id（复用源题），
    作答/错题归集仍指向同一道源题。specs=None：无 AI 生成规格，不支持整卷重生成。
    """
    if child_id is not None:
        child = session.get(User, child_id)
        if child is None or child.parent_id != parent_id:
            raise AppErrorException(ErrCode.TASK_CHILD_NOT_OWNED, "该娃娃不属于你的账号")
    owned = session.exec(
        select(Question).where(
            Question.id.in_(question_ids), Question.parent_id == parent_id
        )
    ).all()
    owned_map = {q.id: q for q in owned}
    if not owned:
        raise AppErrorException(ErrCode.QUESTION_NOT_FOUND, "题库中找不到对应题目")
    if len(owned) != len(set(question_ids)):
        raise AppErrorException(ErrCode.QUESTION_ACCESS_DENIED, "部分题目不存在或无权限")
    task = Task(
        title=title, status="draft", parent_id=parent_id,
        child_id=child_id, specs=None,
    )
    session.add(task)
    session.flush()
    for qid in question_ids:
        q = owned_map[qid]
        session.add(TaskQuestion(
            task_id=task.id,
            question_id=q.id,
            subject=q.subject,
            grade=q.grade,
            knowledge_point=q.knowledge_point,
            qtype=q.qtype,
            stem=q.stem,
            options=q.options,
            answer=q.answer,
            explanation=q.explanation,
            difficulty=q.difficulty,
        ))
    session.commit()
    session.refresh(task)
    return task


def add_bank_questions_to_task(
    *,
    session: Session,
    task_id: uuid.UUID,
    question_ids: list[uuid.UUID],
) -> Task | None:
    """选项 B：把题库题追加到已有草稿（仅本家长拥有的题；同题去重）。

    返回 None 表示任务不存在（路由层转 404）。
    """
    task = session.get(Task, task_id)
    if task is None:
        return None
    existing = {
        tq.question_id
        for tq in session.exec(
            select(TaskQuestion).where(TaskQuestion.task_id == task_id)
        )
    }
    owned = session.exec(
        select(Question).where(
            Question.id.in_(question_ids), Question.parent_id == task.parent_id
        )
    ).all()
    for q in owned:
        if q.id in existing:
            continue
        session.add(TaskQuestion(
            task_id=task.id,
            question_id=q.id,
            subject=q.subject,
            grade=q.grade,
            knowledge_point=q.knowledge_point,
            qtype=q.qtype,
            stem=q.stem,
            options=q.options,
            answer=q.answer,
            explanation=q.explanation,
            difficulty=q.difficulty,
        ))
    session.commit()
    session.refresh(task)
    return task


def get_draft_tasks(*, session: Session, parent_id: uuid.UUID) -> list[Task]:
    """家长草稿列表（供选项 B 的草稿选择器）。"""
    return list(
        session.exec(
            select(Task)
            .where(Task.parent_id == parent_id, Task.status == "draft")
            .order_by(Task.created_at.desc())
        ).all()
    )


def discard_draft_task(*, session: Session, task_id: uuid.UUID) -> bool:
    """作废草稿（R-Q3 四个动作之一）。

    - draft：删除 Task + 删所有草稿 TaskQuestion + 删关联 Question（R-Q5=b）。
    - ready：删除 Task + 删所有 TaskQuestion + 删关联 Question（整卷作废）。
    - assigned/done：不允许，返回 False（路由层应先拒绝）。
    """
    task = session.get(Task, task_id)
    if task is None:
        return False
    if task.status not in ("draft", "ready"):
        return False
    tqs = get_task_questions(session=session, task_id=task.id)
    qids = [tq.question_id for tq in tqs if tq.question_id is not None]
    for tq in tqs:
        session.delete(tq)
    for qid in qids:
        q = session.get(Question, qid)
        if q is not None:
            session.delete(q)
    session.delete(task)
    session.commit()
    return True


def assign_task(
    *, session: Session, task_id: uuid.UUID, child_id: uuid.UUID
) -> Task | None:
    """ready → assigned：派发给娃娃，绑 child_id（ADR-0004 D7）。

    TaskQuestion 创建时已是独立副本，assigned 后只读，无需再深拷贝。
    """
    task = session.get(Task, task_id)
    if task is None or task.status != "ready":
        return None
    task.status = "assigned"
    task.child_id = child_id
    session.add(task)
    session.commit()
    session.refresh(task)
    return task


def get_child_tasks_today(*, session: Session, child_id: uuid.UUID) -> list[Task]:
    """娃娃今日任务：只返回 assigned/done 态（draft/ready 不可见，ADR-0004 D1）。"""
    today = datetime.now(UTC).date()
    return list(
        session.exec(
            select(Task).where(
                Task.child_id == child_id,
                Task.status.in_(["assigned", "done"]),
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


# ───────── 多模型接入（ADR-0015 / 票据 08） ─────────
def list_model_configs(*, session: Session, parent_id: uuid.UUID) -> list[ModelConfig]:
    """家长自定义模型列表（不含 api_key 明文）。"""
    return list(
        session.exec(select(ModelConfig).where(ModelConfig.parent_id == parent_id)).all()
    )


def get_model_config(*, session: Session, id: uuid.UUID, parent_id: uuid.UUID) -> ModelConfig | None:
    """按 id 取自定义模型；越权（非本家长）返回 None。"""
    mc = session.get(ModelConfig, id)
    if mc is None or mc.parent_id != parent_id:
        return None
    return mc


def create_model_config(
    *,
    session: Session,
    parent_id: uuid.UUID,
    label: str,
    provider: str,
    base_url: str | None,
    model_name: str,
    api_key: str | None,
    is_default: bool = False,
) -> ModelConfig:
    if is_default:
        session.execute(
            update(ModelConfig).where(ModelConfig.parent_id == parent_id).values(is_default=False)
        )
    mc = ModelConfig(
        parent_id=parent_id,
        label=label,
        provider=provider,
        base_url=base_url,
        model_name=model_name,
        api_key_enc=encrypt(api_key),
        is_default=is_default,
    )
    session.add(mc)
    session.commit()
    session.refresh(mc)
    return mc


def update_model_config(
    *, session: Session, id: uuid.UUID, parent_id: uuid.UUID, **fields: object
) -> ModelConfig | None:
    mc = get_model_config(session=session, id=id, parent_id=parent_id)
    if mc is None:
        return None
    api_key = fields.pop("api_key", None)
    if api_key is not None:
        mc.api_key_enc = encrypt(api_key)
    if fields.get("is_default"):
        session.execute(
            update(ModelConfig)
            .where(ModelConfig.parent_id == parent_id, ModelConfig.id != id)
            .values(is_default=False)
        )
    for key, value in fields.items():
        if value is not None:
            setattr(mc, key, value)
    session.add(mc)
    session.commit()
    session.refresh(mc)
    return mc


def delete_model_config(*, session: Session, id: uuid.UUID, parent_id: uuid.UUID) -> bool:
    mc = get_model_config(session=session, id=id, parent_id=parent_id)
    if mc is None:
        return False
    session.delete(mc)
    session.commit()
    return True


def get_default_model_config(*, session: Session, parent_id: uuid.UUID) -> ModelConfig | None:
    return session.exec(
        select(ModelConfig).where(
            ModelConfig.parent_id == parent_id, ModelConfig.is_default.is_(True)
        )
    ).first()
