"""题库复用闭环：题库浏览、删除与引用反查（教师作用域）。

- GET /questions：按 teacher 作用域过滤分页浏览题库，含每题复用度 usage_count。
- DELETE /questions：批量硬删题库题，并全量级联清理引用它的数据（任务里的题目副本、
  AnswerRecord、WrongQuestion；任务因此变空则连任务一并删）。返回
  deleted / deleted_tasks / skipped_forbidden 三组 id。
- GET /questions/{question_id}/usages：反查某题被哪些任务引用（闭环「用过 N 次 → 在哪里用」）。
- 写/组卷入口在 tasks.py（POST /tasks/from-bank、POST /tasks/{task_id}/questions/from-bank）。
"""
from uuid import UUID

from fastapi import APIRouter, Query

from app.core.deps import CurrentTeacher, SessionDep
from app.core.pagination import clamp_page_size, encode_cursor
from app.features.materials.scene_fusion import scene_spec_for_read
from app.features.questions.repository import (
    delete_bank_questions,
    get_question_usages,
    list_bank_questions,
    set_bank_questions_archived,
)
from app.features.questions.schemas import (
    ArchiveQuestionsReq,
    ArchiveQuestionsResult,
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
    teacher: CurrentTeacher,
    subject: str | None = None,
    grade: int | None = None,
    knowledge_point: str | None = None,
    qtype: str | None = None,
    keyword: str | None = None,
    archived: str = Query("active", pattern="^(active|archived|all)$"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    cursor: str | None = None,
) -> BankListResp:
    """教师题库浏览（owner 隔离）。学科/年级/知识点/题型/关键词过滤 + 游标分页。

    给了 ``cursor`` 就走 keyset 游标（忽略 ``page``）；不给则退回 offset，兼容旧客户端
    与 AI 查询工具（ADR-0053）。

    ``archived``（ADR-0053 P2）：``active``（默认）/ ``archived`` / ``all``。
    """
    page_size = clamp_page_size(page_size)
    items, total, usage = list_bank_questions(
        session=session,
        teacher_id=teacher.id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        keyword=keyword,
        page=page,
        page_size=page_size,
        cursor=cursor,
        archived=archived,
    )
    # 本页取满才可能有下一页：取不满说明已经是最后一批。
    # 注意不能拿 total 判断——它是取页时的快照，期间插入新题后必然失真。
    next_cursor = (
        encode_cursor(created_at=items[-1].created_at, id_=items[-1].id)
        if items and len(items) == page_size
        else None
    )
    # 同一页里同一 (年级, 学科, 学期, 知识点) 的题共用一份模板解析结果 —— 避免
    # 每题各查一次（同页通常有几十道同知识点的题）。与助手查询工具同一口径。
    scene_cache: dict[tuple, dict | None] = {}
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
                archived_at=q.archived_at,
                semester=q.semester or "",
                # 交互讲解（ADR-0061 §U）：与任务详情 / 错题本走同一个函数，
                # 否则同一道题「任务里有图、题库里没图」。
                scene_spec=scene_spec_for_read(
                    session,
                    snapshot=q.scene_spec,
                    teacher_id=q.teacher_id,
                    subject=q.subject,
                    grade=q.grade,
                    knowledge_point=q.knowledge_point,
                    semester=q.semester,
                    stem=q.stem,
                    options=q.options,
                    cache=scene_cache,
                ),
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
    teacher: CurrentTeacher,
    body: DeleteQuestionsReq,
) -> DeleteQuestionsResult:
    """批量硬删题库题，并全量级联清理引用它的数据。

    被任务引用的题不再「跳过」，而是连任务里的题目副本（TaskQuestion）、作答记录
    （AnswerRecord）、错题（WrongQuestion）一起删；若任务因此失去全部题目则连任务
    一并删。返回 deleted / deleted_tasks / skipped_forbidden 三组 id。
    """
    result = delete_bank_questions(
        session=session, teacher_id=teacher.id, question_ids=body.ids
    )
    return DeleteQuestionsResult(**result)


@router.post("/archive", response_model=ArchiveQuestionsResult)
def archive_questions(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    body: ArchiveQuestionsReq,
) -> ArchiveQuestionsResult:
    """批量归档 / 恢复题库题（ADR-0053 P2）。

    与 DELETE 的分工：删除是「彻底不要了」（被任务引用的题删不掉），归档是
    「先收起来」——被引用也能归档，且随时能恢复。
    """
    result = set_bank_questions_archived(
        session=session,
        teacher_id=teacher.id,
        question_ids=body.ids,
        archived=body.archived,
    )
    return ArchiveQuestionsResult(**result)


@router.get("/{question_id}/usages", response_model=QuestionUsagesResp)
def question_usages(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    question_id: UUID,
) -> QuestionUsagesResp:
    """反查某题库题被哪些任务引用（owner 隔离）。

    闭环「用过 N 次 → 在哪里用」：前端「用过 N 次」标签可点击，弹出引用任务列表并跳转。
    """
    tasks = get_question_usages(
        session=session, teacher_id=teacher.id, question_id=question_id
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
