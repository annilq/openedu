"""题库复用闭环：题库浏览（家长作用域）。

- GET /questions：按 parent 作用域过滤分页浏览题库，含每题复用度 usage_count。
- 写/组卷入口在 tasks.py（POST /tasks/from-bank、POST /tasks/{task_id}/questions/from-bank）。
"""
from fastapi import APIRouter, Query

from app.api.deps import CurrentParent, SessionDep
from app.crud import list_bank_questions
from app.models import BankListResp, BankQuestionItem

router = APIRouter(prefix="/questions", tags=["questions"])


@router.get("", response_model=BankListResp)
def list_bank(
    *,
    session: SessionDep,
    parent: CurrentParent,
    subject: str | None = None,
    grade: int | None = None,
    knowledge_point: str | None = None,
    qtype: str | None = None,
    keyword: str | None = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
) -> BankListResp:
    """家长题库浏览（owner 隔离）。学科/年级/知识点/题型/关键词过滤 + 分页。"""
    items, total, usage = list_bank_questions(
        session=session,
        parent_id=parent.id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        keyword=keyword,
        page=page,
        page_size=page_size,
    )
    return BankListResp(
        items=[
            BankQuestionItem(
                id=q.id,
                subject=q.subject,
                grade=q.grade,
                stem=q.stem,
                options=q.options,
                qtype=q.qtype,
                knowledge_point=q.knowledge_point,
                difficulty=q.difficulty,
                answer=q.answer,
                explanation=q.explanation,
                created_at=q.created_at,
                usage_count=usage.get(q.id, 0),
            )
            for q in items
        ],
        total=total,
        page=page,
        page_size=page_size,
    )
