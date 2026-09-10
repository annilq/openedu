"""Mastery feature service：知识点掌握度看板（REST 路由与查询工具共用）。

把原先写在 ``mastery/router.py`` 里的「越权校验 + 聚合 + 算分 + 组装」整体下沉到此处，
路由退化为薄适配；查询工具直接调 ``get_mastery_for_user``，无需抄第二份。
"""

from __future__ import annotations

from uuid import UUID

from sqlmodel import Session

from app.core.errors import AppErrorException, ErrCode
from app.db.models import User
from app.domain.mastery import compute_mastery_score, mastery_level
from app.features.children.service import require_owned_child
from app.features.mastery.repository import get_knowledge_point_mastery
from app.features.mastery.schemas import KnowledgeMasteryResp, MasteryResp


def build_mastery(*, session: Session, child_id: UUID) -> MasteryResp:
    """纯聚合：算某娃娃的掌握度看板（不做鉴权，供已校验归属的调用方复用）。"""
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


def get_mastery_for_user(
    *, session: Session, user: User, child_id: UUID
) -> MasteryResp:
    """双角色鉴权后取看板：娃娃仅可看自己，家长仅可看自家娃娃。

    错误码/文案与 ADR-0033 之前的路由实现逐字一致（避免 REST 响应体变化）。
    """
    if user.role == "child":
        if child_id != user.id:
            raise AppErrorException(ErrCode.TASK_NOT_OWNED, "这不是你的掌握度")
    else:  # parent
        require_owned_child(
            session=session,
            parent=user,
            child_id=child_id,
            code=ErrCode.TASK_NOT_YOUR_CHILD,
            message="这不是你家娃娃的掌握度",
        )
    return build_mastery(session=session, child_id=child_id)
