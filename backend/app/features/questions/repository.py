"""Repository layer for the questions (bank) feature."""

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, update
from sqlmodel import Session, func, select

from app.core.errors import ErrCode
from app.core.guard import require_owned
from app.core.pagination import apply_keyset, count_of, order_by_keyset
from app.db.models import (
    AnswerRecord,
    Checkin,
    Conversation,
    Question,
    Task,
    TaskQuestion,
    WrongQuestion,
)


def list_bank_questions(
    *,
    session: Session,
    teacher_id: uuid.UUID,
    subject: str | None = None,
    grade: int | None = None,
    knowledge_point: str | None = None,
    qtype: str | None = None,
    keyword: str | None = None,
    since_days: int | None = None,
    archived: str = "active",
    page: int = 1,
    page_size: int = 20,
    cursor: str | None = None,
) -> tuple[list[Question], int, dict[uuid.UUID, int]]:
    """题库浏览（教师作用域）：过滤分页 + 每题被多少 Task 引用的复用度。

    返回 (items, total, usage)，usage 为 question_id -> 引用次数 映射。

    ``since_days``（ADR-0050）：只返回 ``created_at`` 在 ``[now_utc - N 天, now]`` 内的题，
    即「最近添加的题」。0 / None ＝不限时间。

    ``archived``（ADR-0053 P2）：``active``（默认，只要在用）/ ``archived``（只要已归档）/
    ``all``（都要）。默认排除已归档——归档的意义就是「不用再看到」。

    ``cursor``（ADR-0053）：给了就走 keyset 游标分页（忽略 ``page``），否则退回 offset。
    两条路径共用同一组过滤条件与同一套稳定排序，只有取页方式不同——REST 列表走游标
    （新题从顶部插入时 offset 会重复/漏行），AI 查询工具走 offset + 大 ``page_size``
    一次性取够（对话场景不需要翻页）。
    """
    stmt = select(Question).where(Question.teacher_id == teacher_id)
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
    if since_days:
        cutoff = datetime.now(timezone.utc) - timedelta(days=since_days)
        stmt = stmt.where(Question.created_at >= cutoff)
    if archived == "active":
        stmt = stmt.where(Question.archived_at.is_(None))  # type: ignore[union-attr]
    elif archived == "archived":
        stmt = stmt.where(Question.archived_at.is_not(None))  # type: ignore[union-attr]
    total = count_of(session=session, stmt=stmt)
    if cursor:
        page_stmt = apply_keyset(
            stmt,
            ts_column=Question.created_at,
            id_column=Question.id,
            cursor=cursor,
        ).limit(page_size)
    else:
        page_stmt = (
            stmt.order_by(*order_by_keyset(Question.created_at, Question.id))
            .offset((max(1, page) - 1) * page_size)
            .limit(page_size)
        )
    items = list(session.exec(page_stmt).all())
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


def delete_bank_questions(
    *,
    session: Session,
    teacher_id: uuid.UUID,
    question_ids: list[uuid.UUID],
) -> dict[str, list[uuid.UUID]]:
    """批量硬删题库题，并全量级联清理所有引用它的数据。

    级联范围（owner 隔离，只处理本教师拥有的题）：
    - ``TaskQuestion``：删除所有任务里指向该题的快照副本（即「任务中关联的题目」）；
    - ``AnswerRecord`` / ``WrongQuestion``：删除该题的学生作答与错题记录
      （二者 ``question_id`` 为非空外键，不清理会产生悬空 / 外键冲突）；
    - 若某任务因此失去全部题目（``TaskQuestion`` 数为 0），连该任务一并删除
      （含其 ``Checkin``，并将 ``Conversation.ref_task_id`` 置空）。

    不存在 / 非本教师所有的题归为 ``skipped_forbidden``，不删。

    与归档（``set_bank_questions_archived``）的分工：归档是可逆的「先收起来」
    （被引用也能归档、随时恢复）；删除是「彻底不要了」，所以才需要级联清掉
    引用它的副本与记录，否则会破坏外键完整性。
    """
    # 本教师拥有的题（owner 隔离）
    owned = {
        q.id: q
        for q in session.exec(
            select(Question).where(
                Question.id.in_(question_ids), Question.teacher_id == teacher_id
            )
        ).all()
    }

    deleted: list[uuid.UUID] = []
    skipped_forbidden: list[uuid.UUID] = []
    affected_task_ids: set[uuid.UUID] = set()

    for qid in question_ids:
        q = owned.get(qid)
        if q is None:
            skipped_forbidden.append(qid)
            continue
        # 1) 级联删除该题的作答 / 错题记录（question_id 非空外键）。
        session.exec(
            delete(AnswerRecord).where(AnswerRecord.question_id == qid)
        )
        session.exec(
            delete(WrongQuestion).where(WrongQuestion.question_id == qid)
        )
        # 2) 找出并删除所有任务里指向该题的快照副本，记录受影响的任务。
        tq_rows = session.exec(
            select(TaskQuestion).where(TaskQuestion.question_id == qid)
        ).all()
        for tq in tq_rows:
            affected_task_ids.add(tq.task_id)
        session.exec(
            delete(TaskQuestion).where(TaskQuestion.question_id == qid)
        )
        # 3) 删除题库题本身。
        session.delete(q)
        deleted.append(qid)

    # 4) 受影响的任务若已无任何题目，连任务一并删除（含 Checkin，并置空引用它的会话）。
    deleted_tasks: list[uuid.UUID] = []
    if affected_task_ids:
        for tid in affected_task_ids:
            remaining = session.exec(
                select(TaskQuestion).where(TaskQuestion.task_id == tid)
            ).first()
            if remaining is None:
                deleted_tasks.append(tid)
        for tid in deleted_tasks:
            session.exec(delete(Checkin).where(Checkin.task_id == tid))
            session.exec(
                update(Conversation)
                .where(Conversation.ref_task_id == tid)
                .values(ref_task_id=None)
            )
            session.exec(delete(Task).where(Task.id == tid))

    session.commit()
    return {
        "deleted": deleted,
        "deleted_tasks": deleted_tasks,
        "skipped_forbidden": skipped_forbidden,
    }


def set_bank_questions_archived(
    *,
    session: Session,
    teacher_id: uuid.UUID,
    question_ids: list[uuid.UUID],
    archived: bool,
) -> dict[str, list[uuid.UUID]]:
    """批量归档 / 恢复题库题（ADR-0053 P2）。

    与 :func:`delete_bank_questions` 的两点差别，正是归档存在的理由：
    - **被任务引用的题也能归档**：删除会破坏历史任务，归档不会（题还在，只是默认不显示）；
    - **可逆**：``archived=False`` 即恢复。

    owner 隔离：只处理本教师拥有的题；其余归为 skipped_forbidden。
    """
    owned = {
        q.id: q
        for q in session.exec(
            select(Question).where(
                Question.id.in_(question_ids), Question.teacher_id == teacher_id
            )
        ).all()
    }
    now = datetime.now(timezone.utc)
    done: list[uuid.UUID] = []
    skipped_forbidden: list[uuid.UUID] = []
    for qid in question_ids:
        q = owned.get(qid)
        if q is None:
            skipped_forbidden.append(qid)
            continue
        q.archived_at = now if archived else None
        session.add(q)
        done.append(qid)
    session.commit()
    return {"updated": done, "skipped_forbidden": skipped_forbidden}


def get_question_usages(
    *, session: Session, teacher_id: uuid.UUID, question_id: uuid.UUID
) -> list[Task]:
    """反查某题库题被哪些任务引用（owner 隔离）。

    闭环「用过 N 次 → 在哪里用」：通过 TaskQuestion.question_id 反查
    引用该源题的 Task（去重）。题不在本教师题库 → 抛权限错误。
    """
    require_owned(
        session=session,
        owner_id=teacher_id,
        model=Question,
        obj_id=question_id,
        code=ErrCode.QUESTION_ACCESS_DENIED,
        message="该题库题不存在或无权限",
    )
    rows = session.exec(
        select(Task)
        .join(TaskQuestion, TaskQuestion.task_id == Task.id)
        .where(
            TaskQuestion.question_id == question_id,
            Task.teacher_id == teacher_id,
        )
        .order_by(Task.created_at.desc())
    ).all()
    # 理论上 task_id 唯一，去重保险
    seen: set[uuid.UUID] = set()
    unique: list[Task] = []
    for t in rows:
        if t.id not in seen:
            seen.add(t.id)
            unique.append(t)
    return unique
