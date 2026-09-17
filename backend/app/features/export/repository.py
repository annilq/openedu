"""Repository：按来源把「打印导出」需要的题从库里捞出来。

这里只负责**取数 + 归属校验**（后者一律经 ``app.core.guard``，分层不变量
禁止内联 ``parent_id ==`` 比较）；题号、分节、纯文本降级都是装配层
（``document.py``）的事。
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlmodel import Session, select

from app.core.errors import ErrCode
from app.core.guard import require_owned, require_owned_child
from app.db.models import Question, Task, TaskQuestion, WrongQuestion
from app.features.export.document import QuestionGroup, RawQuestion


def _to_raw(row: Question | TaskQuestion) -> RawQuestion:
    return RawQuestion(
        stem=row.stem,
        options=list(row.options or []),
        qtype=row.qtype,
        subject=row.subject,
    )


def load_bank_questions(
    *, session: Session, parent_id: uuid.UUID, question_ids: list[uuid.UUID]
) -> list[RawQuestion]:
    """题库来源：逐题走归属守卫，保持调用方给的顺序（所见即所得）。"""
    rows: list[RawQuestion] = []
    for question_id in question_ids:
        question = require_owned(
            session=session,
            owner_id=parent_id,
            model=Question,
            obj_id=question_id,
            code=ErrCode.QUESTION_ACCESS_DENIED,
            message="题目不存在或无权访问",
        )
        rows.append(_to_raw(question))
    return rows


def load_task_groups(
    *, session: Session, parent_id: uuid.UUID, task_ids: list[uuid.UUID]
) -> list[QuestionGroup]:
    """任务来源：每个任务一节，节内是 ``TaskQuestion`` 深拷贝快照。

    印快照是有意为之：任务创建时即深拷贝题目全字段，纸上印的是「布置那一刻的题」，
    源题日后被编辑不影响已生成的卷子。快照里同样有 ``answer`` / ``explanation``
    字段——在映射成 ``RawQuestion`` 时就**只取题面字段**，不把答案带出去。
    """
    groups: list[QuestionGroup] = []
    for task_id in task_ids:
        task = require_owned(
            session=session,
            owner_id=parent_id,
            model=Task,
            obj_id=task_id,
            code=ErrCode.TASK_NOT_OWNED,
            message="任务不存在或无权访问",
        )
        items = session.exec(
            select(TaskQuestion)
            .where(TaskQuestion.task_id == task_id)
            .order_by(TaskQuestion.created_at, TaskQuestion.id)  # type: ignore[arg-type]
        ).all()
        groups.append(
            QuestionGroup(
                heading=task.title,
                subject=None,
                questions=tuple(_to_raw(item) for item in items),
            )
        )
    return groups


def load_wrong_book_questions(
    *,
    session: Session,
    parent_id: uuid.UUID,
    child_id: uuid.UUID,
    due_only: bool,
) -> list[RawQuestion]:
    """错题来源：某娃娃的**未毕业**错题（毕业 = ``graduated_at`` 非空）。

    ``due_only=True`` = 只取今天到期的，与复习页「当前到期复习项」同一份集合。
    """
    require_owned_child(session=session, owner_id=parent_id, child_id=child_id)
    stmt = (
        select(Question)
        .join(WrongQuestion, WrongQuestion.question_id == Question.id)
        .where(
            WrongQuestion.child_id == child_id,
            WrongQuestion.graduated_at.is_(None),  # type: ignore[union-attr]
        )
    )
    if due_only:
        stmt = stmt.where(
            WrongQuestion.due_at <= datetime.now(timezone.utc)  # type: ignore[operator]
        ).order_by(WrongQuestion.due_at)  # type: ignore[arg-type]
    else:
        stmt = stmt.order_by(WrongQuestion.first_wrong_at.desc())  # type: ignore[union-attr,attr-defined]
    return [_to_raw(row) for row in session.exec(stmt).all()]
