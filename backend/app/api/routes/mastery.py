from uuid import UUID

from fastapi import APIRouter, HTTPException

from app.api.deps import CurrentParent, SessionDep
from app.crud import get_knowledge_point_mastery
from app.domain.mastery import compute_mastery_score, mastery_level
from app.models import KnowledgeMasteryResp, MasteryResp, User

router = APIRouter(prefix="/tasks/children", tags=["mastery"])


@router.get("/{child_id}/mastery", response_model=MasteryResp)
def mastery(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> MasteryResp:
    """家长查看某娃娃的知识点掌握度看板（F-204 / AC-203）。"""
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise HTTPException(status_code=403, detail="Not your child")

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
