"""家长端 AI 伴学答疑日志（F-305）。

保留家长侧「日志可观测」端点（非 AI 生成，故不并入 /api/v1/assistant/chat）：
- GET  /tutor/logs   查看某娃娃的 AI 答疑日志

娃娃端实时答疑已统一收敛到 ``POST /api/v1/assistant/chat``（role=child → 伴学答疑），
原 ``POST /tutor/ask`` 已废弃。每日配额管控（TutorQuota/TutorUsage）已移除。
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter

from app.core.deps import CurrentParent, SessionDep
from app.core.errors import ErrCode
from app.core.guard import require_owned_child
from app.db.models import User
from app.features.tutor.repository import list_tutor_logs
from app.features.tutor.schemas import TutorLogResp

router = APIRouter(prefix="/tutor", tags=["tutor"])


def _own_child(session, parent, child_id: UUID) -> User:
    """校验 child 归属当前家长，返回娃娃；不存在/越权 → 403。

    判定本身委托 ``core.guard``，这里只保留「本端点对外暴露 403 + 该文案」的契约。
    """
    return require_owned_child(
        session=session,
        owner_id=parent.id,
        child_id=child_id,
        code=ErrCode.FORBIDDEN,
        message="Not your child",
    )


@router.get("/logs", response_model=list[TutorLogResp])
def logs(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> list[TutorLogResp]:
    """家长查看某娃娃的 AI 答疑日志（F-305）。越权（非本家长娃娃）→ 403。"""
    child = _own_child(session, parent, child_id)
    rows = list_tutor_logs(session=session, child_id=child.id)
    return [
        TutorLogResp(
            id=r.id,
            grade=r.grade,
            subject=r.subject,
            knowledge_point=r.knowledge_point,
            question=r.question,
            answer=r.answer,
            input_safe=r.input_safe,
            output_safe=r.output_safe,
            blocked=r.blocked,
            created_at=r.created_at,
        )
        for r in rows
    ]
