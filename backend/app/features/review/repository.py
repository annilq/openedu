"""Repository layer for the review feature (spaced-repetition scheduling)."""

import uuid
from datetime import UTC, datetime

from sqlmodel import Session, select

from app.db.models import Question, WrongQuestion
from app.domain.review_scheduler import (
    advance_stage,
    due_after_correct,
    due_after_wrong,
)


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
