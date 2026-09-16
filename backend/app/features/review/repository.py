"""Repository layer for the review feature (spaced-repetition scheduling)."""

import uuid
from datetime import UTC, datetime

from sqlmodel import Session, select

from app.db.models import Question, WrongQuestion


def list_due_wrong_questions(
    *, session: Session, child_id: uuid.UUID
) -> list[tuple[WrongQuestion, Question]]:
    """到期错题（due_at <= now）：遗忘曲线到点后纳入待复习队列（故事 14）。

    毕业（``graduated_at`` 非空）的错题**不进队列**（ADR-0053 P2）：毕业从「物理
    删除」改成「打时间戳」之后，行还在，这里必须显式排除，否则娃娃会一直被要求
    复习已经掌握的题——那正是当初选择删除的原因。
    """
    rows = session.exec(
        select(WrongQuestion, Question)
        .join(Question, Question.id == WrongQuestion.question_id)
        .where(
            WrongQuestion.child_id == child_id,
            WrongQuestion.graduated_at.is_(None),  # type: ignore[union-attr]
            WrongQuestion.due_at <= datetime.now(UTC),
        )
        .order_by(WrongQuestion.due_at.asc())
    ).all()
    return list(rows)
