"""Repository layer for the tasks feature (task lifecycle + answer + progress)."""

import uuid
from datetime import UTC, date, datetime, timedelta

from sqlmodel import Session, func, select

from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned_child
from app.db.models import (
    AnswerRecord,
    Checkin,
    Question,
    Task,
    TaskQuestion,
    WrongQuestion,
)
from app.domain.review_scheduler import due_after_wrong


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
    model: str | None = None,
) -> Task:
    """批量建草稿 Task + 挂草稿项（R-Q1=c：不预写 Question，只写 TaskQuestion）。

    - `specs_dicts`：原始生成规格的 list[dict]，持久化到 Task.specs 以便整卷重生成。
    - `task_questions`：路由层已用出题引擎生成的草稿项（未写 Question）。
      路由层不 commit 直接传进来，避免和 Task 事务拆分。
    - `focus_interest`：兴趣题模式聚焦主题（WF-4），整卷共享，随草稿持久化。
    - `model`：出题所用模型引用（内置 id / ModelConfig id），随草稿持久化以便重生成沿用。
    """
    task = Task(
        title=title,
        status="draft",
        parent_id=parent_id,
        child_id=child_id,
        specs=specs_dicts or None,
        focus_interest=focus_interest,
        model=model,
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


def confirm_task(*, session: Session, task_id: uuid.UUID) -> Task:
    """draft → ready：家长确认锁定题集（CONTEXT 草稿/锁定/派发）。

    R-Q1=c 锁定前校验：所有草稿项 question_id 非空（都已加入题库）。

    失败一律**抛** ``AppErrorException``（错误码即调用方要的语义）。此前用私有
    sentinel 对象做三态返回，把「哪个哨兵对应哪个错误码」这个知识推给了调用方——
    那是本模块的实现细节，不该越过 seam。调用方只要接住 ``AppErrorException``。
    """
    task = session.get(Task, task_id)
    if task is None or task.status != "draft":
        raise AppErrorException(
            ErrCode.TASK_STATUS_DRAFT_REQUIRED, "仅草稿态可执行锁定"
        )
    tqs = get_task_questions(session=session, task_id=task.id)
    if not tqs:
        raise AppErrorException(
            ErrCode.TASK_NO_QUESTIONS, "草稿没有题目，请先生成再锁定"
        )
    if any(tq.question_id is None for tq in tqs):
        raise AppErrorException(
            ErrCode.TASK_LOCK_REQUIRES_ALL_PROMOTED,
            "锁定失败：部分题目仍未加入题库，请重试",
        )
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
        require_owned_child(
            session=session,
            owner_id=parent_id,
            child_id=child_id,
            code=ErrCode.TASK_CHILD_NOT_OWNED,
            message="该娃娃不属于你的账号",
        )
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


def list_tasks_by_parent(
    *, session: Session, parent_id: uuid.UUID, status: str | None = None
) -> list[Task]:
    """家长名下任务（可选按状态过滤），新建在前。

    ``get_draft_tasks`` 是其 ``status="draft"`` 的特例；查询工具走本函数（含各状态）。
    """
    stmt = select(Task).where(Task.parent_id == parent_id)
    if status:
        stmt = stmt.where(Task.status == status)
    return list(session.exec(stmt.order_by(Task.created_at.desc())))


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
