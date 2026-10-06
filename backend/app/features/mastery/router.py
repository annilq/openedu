from uuid import UUID

from fastapi import APIRouter

from app.core.deps import CurrentUser, SessionDep
from app.features.mastery import service as mastery_service
from app.features.mastery.schemas import MasteryResp

router = APIRouter(prefix="/tasks/students", tags=["mastery"])

# 越权校验与看板聚合已下沉到 `app/features/mastery/service.py`（ADR-0033 决策 13）：
# 查询工具与 REST 路由共用同一份，路由只做「接参数 → 调 service」。
# 角色语义：教师仅可看自家学生，学生仅可看自己。


@router.get("/{student_id}/mastery", response_model=MasteryResp)
def mastery(
    *, session: SessionDep, user: CurrentUser, student_id: UUID
) -> MasteryResp:
    """查看某学生的知识点掌握度看板（F-204 / AC-203）。"""
    return mastery_service.get_mastery_for_user(
        session=session, user=user, student_id=student_id
    )
