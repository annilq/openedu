from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException

from app.api.deps import CurrentChild, SessionDep
from app.crud import (
    create_answer_record,
    list_due_wrong_questions,
    mark_review_result,
)
from app.domain import Grader, build_provider
from app.domain.review_scheduler import next_interval_days
from app.models import (
    AnswerResult,
    Question,
    ReviewAnswerSubmit,
    ReviewItemResp,
    WrongQuestion,
)

router = APIRouter(prefix="/review", tags=["review"])


def _review_item_to_resp(wq: WrongQuestion, q: Question) -> ReviewItemResp:
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


@router.get("/due", response_model=list[ReviewItemResp])
def due_reviews(*, session: SessionDep, child: CurrentChild) -> list[ReviewItemResp]:
    """娃娃的待复习队列：遗忘曲线到点的错题（不含答案，防作弊）。"""
    rows = list_due_wrong_questions(session=session, child_id=child.id)
    return [_review_item_to_resp(wq, q) for wq, q in rows]


@router.post("/answer", response_model=AnswerResult)
def answer_review(
    *,
    session: SessionDep,
    child: CurrentChild,
    submit: ReviewAnswerSubmit,
) -> AnswerResult:
    """复习作答：复用与练习一致的批改逻辑，并更新遗忘曲线调度状态。"""
    wq = session.get(WrongQuestion, submit.wrong_question_id)
    if wq is None or wq.child_id != child.id:
        raise HTTPException(status_code=404, detail="Review item not found")
    # 未到期不可作答：防止连对提前毕业绕过遗忘曲线
    now = datetime.now(UTC)
    due = wq.due_at
    if due is not None:
        if due.tzinfo is None:  # SQLite 存 naive UTC
            now = now.replace(tzinfo=None)
        if due > now:
            raise HTTPException(status_code=409, detail="Review item not due yet")
    question = session.get(Question, wq.question_id)
    if question is None:
        raise HTTPException(status_code=404, detail="Question not found")

    grader = Grader(build_provider())
    result = grader.grade(question=question, student_answer=submit.student_answer)
    create_answer_record(
        session=session,
        question_id=question.id,
        child_id=child.id,
        student_answer=submit.student_answer,
        correct=result["correct"],
        score=result["score"],
        source="review",
    )
    mark_review_result(
        session=session,
        wrong_question_id=wq.id,
        correct=result["correct"],
    )
    return AnswerResult(
        correct=result["correct"],
        score=result["score"],
        explanation=question.explanation or result.get("explanation", ""),
    )
