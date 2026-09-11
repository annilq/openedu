"""Repository layer for the questions (bank) feature."""

import uuid

from sqlmodel import Session, func, select

from app.core.errors import ErrCode
from app.core.guard import require_owned
from app.db.models import Question, Task, TaskQuestion


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


def delete_bank_questions(
    *,
    session: Session,
    parent_id: uuid.UUID,
    question_ids: list[uuid.UUID],
) -> dict[str, list[uuid.UUID]]:
    """批量删除题库题；被任务引用（TaskQuestion.question_id 存在）的不删。

    返回 {deleted, skipped_in_use, skipped_forbidden} 三组 id，便于前端汇总提示。
    owner 隔离：只处理本家长拥有的题；其余归为 skipped_forbidden。
    """
    # 本家长拥有的题（owner 隔离）
    owned = {
        q.id: q
        for q in session.exec(
            select(Question).where(
                Question.id.in_(question_ids), Question.parent_id == parent_id
            )
        ).all()
    }
    # 被任意 TaskQuestion 引用的 question_id 集合（question_id 为 None 的草稿题不算引用）
    referenced: set[uuid.UUID] = set()
    if question_ids:
        rows = session.exec(
            select(TaskQuestion.question_id).where(
                TaskQuestion.question_id.in_(question_ids)
            )
        ).all()
        referenced = {r for r in rows if r is not None}

    deleted: list[uuid.UUID] = []
    skipped_in_use: list[uuid.UUID] = []
    skipped_forbidden: list[uuid.UUID] = []
    for qid in question_ids:
        q = owned.get(qid)
        if q is None:
            skipped_forbidden.append(qid)
            continue
        if qid in referenced:
            skipped_in_use.append(qid)
            continue
        session.delete(q)
        deleted.append(qid)
    session.commit()
    return {
        "deleted": deleted,
        "skipped_in_use": skipped_in_use,
        "skipped_forbidden": skipped_forbidden,
    }


def get_question_usages(
    *, session: Session, parent_id: uuid.UUID, question_id: uuid.UUID
) -> list[Task]:
    """反查某题库题被哪些任务引用（owner 隔离）。

    闭环「用过 N 次 → 在哪里用」：通过 TaskQuestion.question_id 反查
    引用该源题的 Task（去重）。题不在本家长题库 → 抛权限错误。
    """
    require_owned(
        session=session,
        owner_id=parent_id,
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
            Task.parent_id == parent_id,
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
