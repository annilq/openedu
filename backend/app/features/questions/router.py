"""题库复用闭环：题库浏览、删除与引用反查（家长作用域）。

- GET /questions：按 parent 作用域过滤分页浏览题库，含每题复用度 usage_count。
- DELETE /questions：批量删除题库题；被任务引用（TaskQuestion.question_id 存在）的题不删，
  返回 deleted / skipped_in_use / skipped_forbidden 三组 id。
- GET /questions/{question_id}/usages：反查某题被哪些任务引用（闭环「用过 N 次 → 在哪里用」）。
- 写/组卷入口在 tasks.py（POST /tasks/from-bank、POST /tasks/{task_id}/questions/from-bank）。
"""
from uuid import UUID

from fastapi import APIRouter, Query

from app.core.deps import CurrentParent, SessionDep
from app.core.pagination import clamp_page_size, encode_cursor
from app.features.questions.repository import (
    delete_bank_questions,
    get_question_usages,
    list_bank_questions,
)
from app.features.questions.schemas import (
    BankListResp,
    BankQuestionItem,
    DeleteQuestionsReq,
    DeleteQuestionsResult,
    QuestionUsageItem,
    QuestionUsagesResp,
)

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
    cursor: str | None = None,
) -> BankListResp:
    """家长题库浏览（owner 隔离）。学科/年级/知识点/题型/关键词过滤 + 游标分页。

    给了 ``cursor`` 就走 keyset 游标（忽略 ``page``）；不给则退回 offset，兼容旧客户端
    与 AI 查询工具（ADR-0053）。
    """
    page_size = clamp_page_size(page_size)
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
        cursor=cursor,
    )
    # 本页取满才可能有下一页：取不满说明已经是最后一批。
    # 注意不能拿 total 判断——它是取页时的快照，期间插入新题后必然失真。
    next_cursor = (
        encode_cursor(created_at=items[-1].created_at, id_=items[-1].id)
        if items and len(items) == page_size
        else None
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
        next_cursor=next_cursor,
    )


@router.delete("", response_model=DeleteQuestionsResult)
def delete_questions(
    *,
    session: SessionDep,
    parent: CurrentParent,
    body: DeleteQuestionsReq,
) -> DeleteQuestionsResult:
    """批量删除题库题：被任务引用（TaskQuestion.question_id 存在）的题不删。

    返回 deleted / skipped_in_use / skipped_forbidden 三组 id。
    """
    result = delete_bank_questions(
        session=session, parent_id=parent.id, question_ids=body.ids
    )
    return DeleteQuestionsResult(**result)


@router.get("/{question_id}/usages", response_model=QuestionUsagesResp)
def question_usages(
    *,
    session: SessionDep,
    parent: CurrentParent,
    question_id: UUID,
) -> QuestionUsagesResp:
    """反查某题库题被哪些任务引用（owner 隔离）。

    闭环「用过 N 次 → 在哪里用」：前端「用过 N 次」标签可点击，弹出引用任务列表并跳转。
    """
    tasks = get_question_usages(
        session=session, parent_id=parent.id, question_id=question_id
    )
    return QuestionUsagesResp(
        items=[
            QuestionUsageItem(
                task_id=t.id,
                title=t.title,
                status=t.status,
                created_at=t.created_at,
            )
            for t in tasks
        ]
    )
