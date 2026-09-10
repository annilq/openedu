"""Review feature service：待复习队列读取（REST 路由与查询工具共用）。

写路径（复习作答 + 遗忘曲线调度）仍在 router 内——它需要 Grader（LLM）与
「未到期不可作答」的状态机判断，属交互事务，不属只读查询面。
"""

from __future__ import annotations

from uuid import UUID

from sqlmodel import Session

from app.db.models import Question, WrongQuestion
from app.domain.review_scheduler import next_interval_days
from app.features.review.repository import list_due_wrong_questions
from app.features.review.schemas import ReviewItemResp


def review_item_to_resp(wq: WrongQuestion, q: Question) -> ReviewItemResp:
    """错题 + 题目 → 复习项响应（含下次间隔，供前端展示遗忘曲线状态）。"""
    return ReviewItemResp(
        wrong_question_id=wq.id,
        question_id=q.id,
        subject=q.subject,
        grade=q.grade,
        knowledge_point=q.knowledge_point,
        qtype=q.qtype,
        stem=q.stem,
        options=q.options,
        explanation=q.explanation or "",
        wrong_count=wq.wrong_count,
        review_stage=wq.review_stage,
        next_interval_days=next_interval_days(wq.review_stage),
        due_at=wq.due_at,
    )


def list_due_reviews(*, session: Session, child_id: UUID) -> list[ReviewItemResp]:
    """娃娃的待复习队列：遗忘曲线到点的错题（不含答案，防作弊）。"""
    rows = list_due_wrong_questions(session=session, child_id=child_id)
    return [review_item_to_resp(wq, q) for wq, q in rows]
