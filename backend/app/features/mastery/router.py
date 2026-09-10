from uuid import UUID

from fastapi import APIRouter

from app.core.deps import CurrentUser, SessionDep
from app.features.mastery import service as mastery_service
from app.features.mastery.schemas import MasteryResp

router = APIRouter(prefix="/tasks/children", tags=["mastery"])

# 越权校验与看板聚合已下沉到 `app/features/mastery/service.py`（ADR-0033 决策 13）：
# 查询工具与 REST 路由共用同一份，路由只做「接参数 → 调 service」。
# 角色语义：家长仅可看自家娃娃，娃娃仅可看自己。


@router.get("/{child_id}/mastery", response_model=MasteryResp)
def mastery(
    *, session: SessionDep, user: CurrentUser, child_id: UUID
) -> MasteryResp:
    """查看某娃娃的知识点掌握度看板（F-204 / AC-203）。"""
    return mastery_service.get_mastery_for_user(
        session=session, user=user, child_id=child_id
    )
