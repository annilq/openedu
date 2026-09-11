from fastapi import APIRouter, HTTPException

from app.core.deps import CurrentChild, SessionDep
from app.features.review import service as review_service
from app.features.review.schemas import ReviewAnswerSubmit, ReviewItemResp
from app.features.tasks.schemas import AnswerResult

router = APIRouter(prefix="/review", tags=["review"])

# 待复习队列序列化 + 间隔计算、复习作答写路径（批改 + 遗忘曲线调度）均在
# `app/features/review/service.py`（REST 与 ADR-0033 查询工具共用同一套领域规则）。
# 本文件只做 HTTP 适配：鉴权 → 调 service → 把领域异常翻译成状态码。


@router.get("/due", response_model=list[ReviewItemResp])
def due_reviews(*, session: SessionDep, child: CurrentChild) -> list[ReviewItemResp]:
    """娃娃的待复习队列：遗忘曲线到点的错题（不含答案，防作弊）。"""
    return review_service.list_due_reviews(session=session, child_id=child.id)


@router.post("/answer", response_model=AnswerResult)
def answer_review(
    *, session: SessionDep, child: CurrentChild, submit: ReviewAnswerSubmit
) -> AnswerResult:
    """复习作答：复用与练习一致的批改逻辑，并更新遗忘曲线调度状态。"""
    try:
        return review_service.submit_answer(
            session=session, child_id=child.id, submit=submit
        )
    except review_service.ReviewNotFound:
        raise HTTPException(status_code=404, detail="Review item not found")
    except review_service.ReviewNotDue:
        raise HTTPException(status_code=409, detail="Review item not due yet")
