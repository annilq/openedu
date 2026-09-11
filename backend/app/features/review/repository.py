"""Repository layer for the review feature (spaced-repetition scheduling)."""

import uuid
from datetime import UTC, datetime

from sqlmodel import Session, select

from app.db.models import Question, WrongQuestion


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
