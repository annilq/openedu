"""Review feature service.

待复习队列读取（REST 路由与查询工具共用）+ 复习作答写路径（批改 + 遗忘曲线调度）。

写路径原先混在 router 内（含 ``due`` 守卫的 HTTPException），现收口到本模块：
- ``due`` 守卫与归属校验提升为领域异常（``ReviewNotDue`` / ``ReviewNotFound``），
  router 仅做 HTTP 翻译，与 ADR-0033 的查询工具共用同一套领域规则；
- 遗忘曲线状态机委托 ``app.domain.review_scheduler.apply_review_outcome``
  （与练习答错归集共用单一事实源）。
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlmodel import Session

from app.core.ai_plumbing import build_ai_provider
from app.db.models import Question, WrongQuestion
from app.domain import Grader
from app.domain.review_scheduler import apply_review_outcome, next_interval_days
from app.features.review.repository import list_due_wrong_questions
from app.features.review.schemas import ReviewAnswerSubmit, ReviewItemResp
from app.features.tasks.repository import create_answer_record
from app.features.tasks.schemas import AnswerResult


class ReviewNotFound(Exception):
    """复习项不存在或不属于该娃娃（路由翻译为 404）。"""


class ReviewNotDue(Exception):
    """复习项尚未到期，不可作答（路由翻译为 409）。"""


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


def submit_answer(
    *, session: Session, child_id: UUID, submit: ReviewAnswerSubmit
) -> AnswerResult:
    """复习作答：批改 + 落库 + 遗忘曲线调度（写路径收口于此，router 仅做 HTTP 翻译）。

    raises ReviewNotFound: 复习项不存在/不归属该娃娃，或对应题目不存在。
    raises ReviewNotDue: 复习项尚未到期（防止连对提前毕业绕过遗忘曲线）。
    """
    wq = session.get(WrongQuestion, submit.wrong_question_id)
    if wq is None or wq.child_id != child_id:
        raise ReviewNotFound()
    # 未到期不可作答：防止连对提前毕业绕过遗忘曲线
    now = datetime.now(UTC)
    due = wq.due_at
    if due is not None:
        if due.tzinfo is None:  # SQLite 存 naive UTC
            now = now.replace(tzinfo=None)
        if due > now:
            raise ReviewNotDue()
    question = session.get(Question, wq.question_id)
    if question is None:
        raise ReviewNotFound()

    # 批改经归一封装构造 provider（ADR-0034 Phase 2）；复习作答不携带 per-task model，
    # 回落全局 LLM_PROVIDER，统一走 ai_plumbing 单一入口。
    grader = Grader(build_ai_provider())
    result = grader.grade(question=question, student_answer=submit.student_answer)
    create_answer_record(
        session=session,
        question_id=question.id,
        child_id=child_id,
        student_answer=submit.student_answer,
        correct=result["correct"],
        score=result["score"],
        source="review",
    )
    apply_review_outcome(session=session, wq=wq, correct=result["correct"])
    return AnswerResult(
        correct=result["correct"],
        score=result["score"],
        explanation=question.explanation or result.get("explanation", ""),
    )
