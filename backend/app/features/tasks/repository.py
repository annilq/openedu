"""Repository layer for the tasks feature (task lifecycle + answer + progress)."""

import uuid
from datetime import UTC, date, datetime, timedelta

from sqlmodel import Session, func, select

from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned_student
from app.core.pagination import apply_keyset, count_of, order_by_keyset
from app.db.models import (
    AnswerRecord,
    Checkin,
    Question,
    Task,
    TaskAssignment,
    TaskQuestion,
    WrongQuestion,
)
from app.domain.review_scheduler import apply_review_outcome, due_after_wrong


def question_to_task_question(*, q: Question, task_id: uuid.UUID) -> TaskQuestion:
    """题库 Question → 草稿 TaskQuestion（深拷贝字段，不预写 question_id 以外）。

    选项 A（从题库新建）/ 选项 B（追加题库题）两条「从题库建题」路径共用同一份
    字段映射（单一事实源），避免 10 字段逐字复制在多处漂移。
    """
    return TaskQuestion(
        task_id=task_id,
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
    )


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
    teacher_id: uuid.UUID,
    title: str,
    student_id: uuid.UUID | None,
    specs_dicts: list[dict],
    task_questions: list[TaskQuestion],
    model: str | None = None,
) -> Task:
    """批量建草稿 Task + 挂草稿项（R-Q1=c：不预写 Question，只写 TaskQuestion）。

    - `specs_dicts`：原始生成规格的 list[dict]，持久化到 Task.specs 以便整卷重生成。
    - `task_questions`：路由层已用出题引擎生成的草稿项（未写 Question）。
      路由层不 commit 直接传进来，避免和 Task 事务拆分。
    - `model`：出题所用模型引用（内置 id / ModelConfig id），随草稿持久化以便重生成沿用。
    """
    task = Task(
        title=title,
        status="draft",
        teacher_id=teacher_id,
        student_id=student_id,
        specs=specs_dicts or None,
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


def update_task_meta(
    *,
    session: Session,
    task_id: uuid.UUID,
    edits: dict,
) -> Task | None:
    """编辑任务元信息（仅 draft 态，路由层校验；当前仅 title 在可改字段内）。"""
    task = get_task(session=session, task_id=task_id)
    if task is None:
        return None
    for k, v in edits.items():
        setattr(task, k, v)
    session.add(task)
    session.commit()
    session.refresh(task)
    return task


def confirm_task(*, session: Session, task_id: uuid.UUID) -> Task:
    """draft → ready：教师确认锁定题集（CONTEXT 草稿/锁定/派发）。

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
        teacher_id=session.get(Task, tq.task_id).teacher_id,  # owner 隔离（闭环）
        subject=tq.subject,
        grade=tq.grade,
        knowledge_point=tq.knowledge_point,
        qtype=tq.qtype,
        stem=tq.stem,
        options=tq.options,
        multi=tq.multi,
        answer=tq.answer,
        explanation=tq.explanation,
        difficulty=tq.difficulty,
        semester=tq.semester,
        # 场景快照随草稿一起进题库（ADR-0061 §M）：草稿期算好的那份就是这道题
        # 的讲解实例，入库后不再依赖知识点模板是否被改动。
        scene_spec=tq.scene_spec,
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
      教师后续还需要点「加入题库」才真正入 Question 表。
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
    若传入 specs_dicts 则更新 Task.specs（教师在 UI 上调整了规格）。
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
    teacher_id: uuid.UUID,
    title: str,
    student_id: uuid.UUID | None = None,
    question_ids: list[uuid.UUID],
) -> Task:
    """选项 A：从题库新建任务（draft）。

    深拷贝选中题为 TaskQuestion 并回填 question_id（复用源题），
    作答/错题归集仍指向同一道源题。specs=None：无 AI 生成规格，不支持整卷重生成。
    """
    if student_id is not None:
        require_owned_student(
            session=session,
            owner_id=teacher_id,
            student_id=student_id,
            code=ErrCode.TASK_CHILD_NOT_OWNED,
            message="该学生不属于你的账号",
        )
    owned = session.exec(
        select(Question).where(
            Question.id.in_(question_ids), Question.teacher_id == teacher_id
        )
    ).all()
    owned_map = {q.id: q for q in owned}
    if not owned:
        raise AppErrorException(ErrCode.QUESTION_NOT_FOUND, "题库中找不到对应题目")
    if len(owned) != len(set(question_ids)):
        raise AppErrorException(ErrCode.QUESTION_ACCESS_DENIED, "部分题目不存在或无权限")
    task = Task(
        title=title, status="draft", teacher_id=teacher_id,
        student_id=student_id, specs=None,
    )
    session.add(task)
    session.flush()
    for qid in question_ids:
        q = owned_map[qid]
        session.add(question_to_task_question(q=q, task_id=task.id))
    session.commit()
    session.refresh(task)
    return task


def add_bank_questions_to_task(
    *,
    session: Session,
    task_id: uuid.UUID,
    question_ids: list[uuid.UUID],
) -> Task | None:
    """选项 B：把题库题追加到已有草稿（仅本教师拥有的题；同题去重）。

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
            Question.id.in_(question_ids), Question.teacher_id == task.teacher_id
        )
    ).all()
    for q in owned:
        if q.id in existing:
            continue
        session.add(question_to_task_question(q=q, task_id=task.id))
    session.commit()
    session.refresh(task)
    return task


def get_draft_tasks(*, session: Session, teacher_id: uuid.UUID) -> list[Task]:
    """教师草稿列表（供选项 B 的草稿选择器）。"""
    return list(
        session.exec(
            select(Task)
            .where(Task.teacher_id == teacher_id, Task.status == "draft")
            .order_by(Task.created_at.desc())
        ).all()
    )


def _status_clause(status: str | None):  # noqa: ANN202
    """状态过滤条件；``status`` 允许逗号分隔的多个状态（教师任务页的 Tab）。

    前端「草稿」Tab 实际是 draft + ready 两个状态——若按单状态过滤，要么把 ready
    藏在列表里，要么客户端在已加载页里过滤（分页后就不准了）。逗号分隔让 Tab 的
    语义留在服务端，分页与计数都跟着同一份条件走。
    """
    if not status:
        return None
    values = [s.strip() for s in status.split(",") if s.strip()]
    if not values:
        return None
    if len(values) == 1:
        return Task.status == values[0]
    return Task.status.in_(values)


def list_tasks_by_teacher(
    *,
    session: Session,
    teacher_id: uuid.UUID,
    status: str | None = None,
    page_size: int | None = None,
    cursor: str | None = None,
) -> list[Task]:
    """教师名下任务（可选按状态过滤），新建在前。

    ``get_draft_tasks`` 是其 ``status="draft"`` 的特例；查询工具走本函数（含各状态）。

    ``cursor`` / ``page_size``（ADR-0053）：给了游标就走 keyset，两者都给 None 则
    不分页（AI 查询工具与旧调用点行为不变）。
    """
    stmt = select(Task).where(Task.teacher_id == teacher_id)
    clause = _status_clause(status)
    if clause is not None:
        stmt = stmt.where(clause)
    if page_size is None:
        return list(session.exec(stmt.order_by(*order_by_keyset(Task.created_at, Task.id))))
    if cursor:
        return list(
            session.exec(
                apply_keyset(
                    stmt,
                    ts_column=Task.created_at,
                    id_column=Task.id,
                    cursor=cursor,
                ).limit(page_size)
            )
        )
    return list(
        session.exec(
            stmt.order_by(*order_by_keyset(Task.created_at, Task.id)).limit(page_size)
        )
    )


def count_tasks_by_teacher(
    *, session: Session, teacher_id: uuid.UUID, status: str | None = None
) -> int:
    """教师名下任务总数（过滤条件与 :func:`list_tasks_by_teacher` 一致）。"""
    stmt = select(Task).where(Task.teacher_id == teacher_id)
    clause = _status_clause(status)
    if clause is not None:
        stmt = stmt.where(clause)
    return count_of(session=session, stmt=stmt)


def count_tasks_by_teacher_grouped(
    *, session: Session, teacher_id: uuid.UUID
) -> dict[str, int]:
    """按状态分组计数（教师任务页三个 Tab 的徽标）。

    一次 group by 取全部分组，不为每个状态发一条查询——四个状态四条查询在列表接口
    里是纯粹的浪费。
    """
    rows = session.exec(
        select(Task.status, func.count())
        .where(Task.teacher_id == teacher_id)
        .group_by(Task.status)
    ).all()
    return {status: n for status, n in rows}


def count_incomplete_assignments_by_teacher(
    *, session: Session, teacher_id: uuid.UUID
) -> int:
    """教师名下任务中，尚未提交作答的派发对象数（ADR-0069/0070，ticket 20）。

    派发事实源是 ``taskassignment`` 表；``completed_at`` 为空 = 该学生未完成。
    必须按 ``Task.teacher_id`` 收敛到当前教师，否则会数到别的教师的派发。
    """
    stmt = (
        select(TaskAssignment)
        .join(Task, TaskAssignment.task_id == Task.id)
        .where(Task.teacher_id == teacher_id)
        .where(TaskAssignment.completed_at.is_(None))
    )
    return count_of(session=session, stmt=stmt)


def task_question_breakdown(
    *, session: Session, task_ids: list[uuid.UUID]
) -> dict[uuid.UUID, list[tuple[str, int]]]:
    """每任务按学科的题数分布：``task_id -> [(subject, count), ...]``。

    任务列表摘要的题目数与学科标签都从这里派生——**一次查询替代 N+1**
    （此前列表对每个任务调一次 ``get_task_questions``，只为数个数）。
    """
    if not task_ids:
        return {}
    rows = session.exec(
        select(TaskQuestion.task_id, TaskQuestion.subject, func.count())
        .where(TaskQuestion.task_id.in_(task_ids))
        .group_by(TaskQuestion.task_id, TaskQuestion.subject)
    ).all()
    out: dict[uuid.UUID, list[tuple[str, int]]] = {}
    for task_id, subject, n in rows:
        out.setdefault(task_id, []).append((subject, n))
    return out


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
    *, session: Session, task_id: uuid.UUID, student_id: uuid.UUID
) -> Task | None:
    """ready → assigned：派发给学生，绑 student_id（ADR-0004 D7）。

    TaskQuestion 创建时已是独立副本，assigned 后只读，无需再深拷贝。
    """
    task = session.get(Task, task_id)
    if task is None or task.status != "ready":
        return None
    task.status = "assigned"
    task.student_id = student_id
    session.add(task)
    session.commit()
    session.refresh(task)
    return task


def get_student_tasks_today(*, session: Session, student_id: uuid.UUID) -> list[Task]:
    """学生今日任务：只返回 assigned/done 态（draft/ready 不可见，ADR-0004 D1）。

    学生可见范围 = legacy 单列 ``task.student_id`` 命中 **或** 在派发关系里（多学生派发，
    ADR-0069）——两条来源并集，保证整班派发的任务也能出现在该学生今日列表。
    """
    today = datetime.now(UTC).date()
    assigned_ids = select(TaskAssignment.task_id).where(
        TaskAssignment.student_id == student_id
    )
    return list(
        session.exec(
            select(Task).where(
                Task.status.in_(["assigned", "done"]),
                func.date(Task.created_at) == today,
                (Task.id.in_(assigned_ids)) | (Task.student_id == student_id),
            )
        )
    )


# ───────── 作业派发关系（ADR-0069） ─────────
def create_task_assignment(
    *, session: Session, task_id: uuid.UUID, student_id: uuid.UUID
) -> TaskAssignment:
    """写入单条派发关系（幂等：已存在则直接返回现有行）。"""
    existing = session.exec(
        select(TaskAssignment).where(
            TaskAssignment.task_id == task_id,
            TaskAssignment.student_id == student_id,
        )
    ).first()
    if existing is not None:
        return existing
    ta = TaskAssignment(task_id=task_id, student_id=student_id)
    session.add(ta)
    session.commit()
    session.refresh(ta)
    return ta


def bulk_create_assignments(
    *, session: Session, task_id: uuid.UUID, student_ids: list[uuid.UUID]
) -> int:
    """原子写入一批派发关系（按学生去重），返回实际新增条数。

    已在关系里的学生不重复写；整批在一个事务内提交，部分失败整体回滚。
    """
    if not student_ids:
        return 0
    existing_ids = set(
        row[0]
        for row in session.exec(
            select(TaskAssignment.student_id).where(
                TaskAssignment.task_id == task_id,
                TaskAssignment.student_id.in_(student_ids),
            )
        ).all()
    )
    to_add = [sid for sid in dict.fromkeys(student_ids) if sid not in existing_ids]
    for sid in to_add:
        session.add(TaskAssignment(task_id=task_id, student_id=sid))
    session.commit()
    return len(to_add)


def get_assigned_student_ids(
    *, session: Session, task_id: uuid.UUID
) -> list[uuid.UUID]:
    """某任务全部派发对象的学生 id（去重天然由 UNIQUE 约束保证）。"""
    return list(
        session.exec(
            select(TaskAssignment.student_id)
            .where(TaskAssignment.task_id == task_id)
            .order_by(TaskAssignment.student_id)
        ).all()
    )


def count_assignments(*, session: Session, task_id: uuid.UUID) -> int:
    return session.scalar(
        select(func.count())
        .select_from(TaskAssignment)
        .where(TaskAssignment.task_id == task_id)
    ) or 0


def count_completed_assignments(*, session: Session, task_id: uuid.UUID) -> int:
    return session.scalar(
        select(func.count())
        .select_from(TaskAssignment)
        .where(
            TaskAssignment.task_id == task_id,
            TaskAssignment.completed_at.is_not(None),  # type: ignore[union-attr]
        )
    ) or 0


def mark_assignment_completed(
    *, session: Session, task_id: uuid.UUID, student_id: uuid.UUID
) -> None:
    """把某学生在该任务的派发关系标为已完成（completed_at=now）。"""
    ta = session.exec(
        select(TaskAssignment).where(
            TaskAssignment.task_id == task_id,
            TaskAssignment.student_id == student_id,
        )
    ).first()
    if ta is None:
        # 兜底：关系缺失时补一行（不应发生，仅防御并发竞态）。
        ta = TaskAssignment(task_id=task_id, student_id=student_id)
        session.add(ta)
    if ta.completed_at is None:
        ta.completed_at = datetime.now(UTC)
    session.add(ta)
    session.commit()


def cancel_assignments(*, session: Session, task_id: uuid.UUID) -> int:
    """删除某任务全部派发关系，返回删除条数（取消派发 / 取消全部）。"""
    rows = session.exec(
        select(TaskAssignment).where(TaskAssignment.task_id == task_id)
    ).all()
    n = len(rows)
    for ta in rows:
        session.delete(ta)
    session.commit()
    return n


def is_student_assigned(
    *, session: Session, task_id: uuid.UUID, student_id: uuid.UUID
) -> bool:
    """该学生是否在本任务的派发关系里（多学生派发下作答/打卡的可答判定）。"""
    return (
        session.exec(
            select(TaskAssignment.id).where(
                TaskAssignment.task_id == task_id,
                TaskAssignment.student_id == student_id,
            )
        ).first()
        is not None
    )


# ───────── 作答 / 打卡 / 进度 ─────────
def create_answer_record(
    *,
    session: Session,
    question_id: uuid.UUID,
    student_id: uuid.UUID,
    student_answer: str,
    correct: bool,
    score: float,
    source: str = "practice",
) -> AnswerRecord:
    rec = AnswerRecord(
        question_id=question_id,
        student_id=student_id,
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
    student_id: uuid.UUID,
    task_id: uuid.UUID,
    checkin_date: date,
) -> Checkin:
    existing = session.exec(
        select(Checkin).where(
            Checkin.student_id == student_id,
            Checkin.task_id == task_id,
            Checkin.checkin_date == checkin_date,
        )
    ).first()
    if existing:
        return existing
    c = Checkin(student_id=student_id, task_id=task_id, checkin_date=checkin_date)
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


def get_progress(*, session: Session, student_id: uuid.UUID) -> tuple[int, int, int, int]:
    total = (
        session.scalar(
            select(func.count(AnswerRecord.id)).where(
                AnswerRecord.student_id == student_id
            )
        )
        or 0
    )
    correct = (
        session.scalar(
            select(func.count(AnswerRecord.id)).where(
                AnswerRecord.student_id == student_id,
                AnswerRecord.correct == True,  # noqa: E712
            )
        )
        or 0
    )
    checkin_dates = list(
        session.exec(select(Checkin.checkin_date).where(Checkin.student_id == student_id)).all()
    )
    checkin_days = len(set(checkin_dates))
    streak = _compute_streak(checkin_dates)
    return total, correct, checkin_days, streak


# ───────── 错题集 / 遗忘曲线复习 ─────────
def upsert_wrong_question(
    *,
    session: Session,
    question_id: uuid.UUID,
    student_id: uuid.UUID,
) -> WrongQuestion:
    """答错归集错题（故事 13）：已存在则次数 +1 不建多条。

    已存在的错题重置遗忘曲线计时器（故事 17）复用 ``apply_review_outcome`` 单一事实源
    （与复习作答同一条状态机）；首次归集新建首档 1 天。
    """
    existing = session.exec(
        select(WrongQuestion).where(
            WrongQuestion.student_id == student_id,
            WrongQuestion.question_id == question_id,
        )
    ).first()
    if existing:
        return apply_review_outcome(session=session, wq=existing, correct=False)
    now = datetime.now(UTC)
    wq = WrongQuestion(
        student_id=student_id,
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
    *,
    session: Session,
    student_id: uuid.UUID,
    page_size: int | None = None,
    cursor: str | None = None,
    scope: str = "active",
) -> list[tuple[WrongQuestion, Question]]:
    """错题列表：join Question 取完整题目，按首次错时间倒序。

    ``cursor`` / ``page_size``（ADR-0053）：给了游标就走 keyset，两者都给 None 则
    不分页（AI 查询工具行为不变）。

    ``scope``（ADR-0053 P2）：``active``（默认，未毕业）/ ``graduated``（只看已掌握）。
    毕业（末位阶段答对）不再物理删除，而是打 ``graduated_at`` 时间戳——默认过滤掉，
    但痕迹留着，教师端「已掌握」分区能翻出来看。
    """
    stmt = (
        select(WrongQuestion, Question)
        .join(Question, Question.id == WrongQuestion.question_id)
        .where(WrongQuestion.student_id == student_id)
    )
    if scope == "active":
        stmt = stmt.where(WrongQuestion.graduated_at.is_(None))  # type: ignore[union-attr]
    elif scope == "graduated":
        stmt = stmt.where(WrongQuestion.graduated_at.is_not(None))  # type: ignore[union-attr]
    if page_size is None:
        return list(
            session.exec(
                stmt.order_by(
                    *order_by_keyset(WrongQuestion.first_wrong_at, WrongQuestion.id)
                )
            )
        )
    if cursor:
        return list(
            session.exec(
                apply_keyset(
                    stmt,
                    ts_column=WrongQuestion.first_wrong_at,
                    id_column=WrongQuestion.id,
                    cursor=cursor,
                ).limit(page_size)
            )
        )
    return list(
        session.exec(
            stmt.order_by(
                *order_by_keyset(WrongQuestion.first_wrong_at, WrongQuestion.id)
            ).limit(page_size)
        )
    )


def count_wrong_questions(
    *, session: Session, student_id: uuid.UUID, scope: str = "active"
) -> int:
    """错题总数（过滤条件与 :func:`list_wrong_questions` 一致）。

    ``scope`` 同 :func:`list_wrong_questions`；``graduated`` 即「已掌握」条数，
    用于教师端「已掌握（N）」分区标题。
    """
    stmt = select(WrongQuestion).where(WrongQuestion.student_id == student_id)
    if scope == "active":
        stmt = stmt.where(WrongQuestion.graduated_at.is_(None))  # type: ignore[union-attr]
    elif scope == "graduated":
        stmt = stmt.where(WrongQuestion.graduated_at.is_not(None))  # type: ignore[union-attr]
    return count_of(session=session, stmt=stmt)


def rejoin_wrong_question(
    *, session: Session, student_id: uuid.UUID, wrong_id: uuid.UUID
) -> WrongQuestion:
    """把已毕业（已掌握）的错题重新加入复习（ADR-0053 P2）。

    清 ``graduated_at``、阶段归 0、``due_at = now``（立刻可复习），保留 ``wrong_count``
    与 ``first_wrong_at``——学习痕迹不因为「重新来过」而清零。

    归属判据走 ``student_id`` 作用域查询（不是手写 ``==`` 比较后内联判定）：找不到即
    抛不存在，避免跨学生改数据。
    """
    wq = session.exec(
        select(WrongQuestion).where(
            WrongQuestion.id == wrong_id, WrongQuestion.student_id == student_id
        )
    ).first()
    if wq is None:
        raise AppErrorException(
            ErrCode.WRONG_QUESTION_NOT_FOUND, "该错题不存在或无权限"
        )
    now = datetime.now(UTC)
    wq.graduated_at = None
    wq.review_stage = 0
    wq.due_at = now
    wq.last_wrong_at = now
    session.add(wq)
    session.commit()
    session.refresh(wq)
    return wq
