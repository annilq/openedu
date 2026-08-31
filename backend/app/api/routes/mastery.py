from uuid import UUID

from fastapi import APIRouter

from app.api.deps import CurrentUser, SessionDep
from app.core.errors import AppErrorException, ErrCode
from app.crud import get_knowledge_point_mastery
from app.domain.mastery import compute_mastery_score, mastery_level
from app.models import KnowledgeMasteryResp, MasteryResp, User

router = APIRouter(prefix="/tasks/children", tags=["mastery"])


@router.get("/{child_id}/mastery", response_model=MasteryResp)
def mastery(
    *, session: SessionDep, user: CurrentUser, child_id: UUID
) -> MasteryResp:
    """查看某娃娃的知识点掌握度看板（F-204 / AC-203）。

    家长可查看自家娃娃；娃娃仅可查看自己的掌握度（双角色分支，
    与 tasks.py 的作答/打卡接口保持一致）。
    """
    if user.role == "child":
        if child_id != user.id:
            raise AppErrorException(ErrCode.TASK_NOT_OWNED, "这不是你的掌握度")
        child = user
    else:  # parent
        child = session.get(User, child_id)
        if child is None or child.parent_id != user.id:
            raise AppErrorException(
                ErrCode.TASK_NOT_YOUR_CHILD, "这不是你家娃娃的掌握度"
            )

    items: list[KnowledgeMasteryResp] = []
    for agg in get_knowledge_point_mastery(session=session, child_id=child_id):
        score = compute_mastery_score(
            total_answers=agg.total_answers,
            correct_answers=agg.correct_answers,
            recent_total=agg.recent_total,
            recent_correct=agg.recent_correct,
            active_wrong=agg.active_wrong,
            max_review_stage=agg.max_review_stage,
        )
        items.append(
            KnowledgeMasteryResp(
                knowledge_point=agg.knowledge_point,
                subject=agg.subject,
                grade=agg.grade,
                total_answers=agg.total_answers,
                correct_answers=agg.correct_answers,
                accuracy=round(agg.correct_answers / agg.total_answers, 2)
                if agg.total_answers
                else 0.0,
                active_wrong=agg.active_wrong,
                max_review_stage=agg.max_review_stage,
                score=score,
                level=mastery_level(
                    total_answers=agg.total_answers,
                    score=score,
                    active_wrong=agg.active_wrong,
                ),
            )
        )
    return MasteryResp(
        child_id=child_id,
        total_knowledge_points=len(items),
        mastered_count=sum(1 for i in items if i.level == "已掌握"),
        items=items,
    )
