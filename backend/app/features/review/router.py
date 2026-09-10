from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException

from app.core.deps import CurrentChild, SessionDep
from app.db.models import Question, WrongQuestion
from app.domain import Grader, build_provider
from app.features.review import service as review_service
from app.features.review.repository import mark_review_result
from app.features.review.schemas import ReviewAnswerSubmit, ReviewItemResp
from app.features.tasks.repository import create_answer_record
from app.features.tasks.schemas import AnswerResult

router = APIRouter(prefix="/review", tags=["review"])

# 待复习队列的序列化 + 间隔计算在 `app/features/review/service.py`
# （REST 与 ADR-0033 查询工具共用）；作答写路径（批改 + 遗忘曲线调度）留在本文件。


@router.get("/due", response_model=list[ReviewItemResp])
def due_reviews(*, session: SessionDep, child: CurrentChild) -> list[ReviewItemResp]:
    """娃娃的待复习队列：遗忘曲线到点的错题（不含答案，防作弊）。"""
    return review_service.list_due_reviews(session=session, child_id=child.id)


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
