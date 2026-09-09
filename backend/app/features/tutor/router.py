"""家长端 AI 使用管控与答疑日志（T10，故事 23/26 / F-305）。

保留家长侧「管控 + 可观测」端点（非 AI 生成，故不并入 /api/v1/assistant/chat）：
- GET  /tutor/logs   查看某娃娃的 AI 答疑日志
- GET  /tutor/quota   查看某娃娃的 AI 使用管控配置
- PUT  /tutor/quota   设置某娃娃的 AI 使用管控
- GET  /tutor/usage   查看某娃娃当日 AI 用量

娃娃端实时答疑已统一收敛到 ``POST /api/v1/assistant/chat``（role=child → 伴学答疑），
原 ``POST /tutor/ask`` 已废弃。
"""
from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException

from app.core.config import settings
from app.core.deps import CurrentParent, SessionDep
from app.db.models import User
from app.domain import validate_quota_config
from app.domain.quota import resolve_quota_limits
from app.features.tutor.repository import (
    count_tutor_today,
    get_tutor_quota,
    get_tutor_usage_today,
    list_tutor_logs,
    upsert_tutor_quota,
)
from app.features.tutor.schemas import (
    TutorLogResp,
    TutorQuotaResp,
    TutorQuotaUpdate,
    TutorUsageResp,
)

router = APIRouter(prefix="/tutor", tags=["tutor"])


def _own_child(session, parent, child_id: UUID) -> User:
    """校验 child 归属当前家长，返回娃娃；不存在/越权 → 403。"""
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise HTTPException(status_code=403, detail="Not your child")
    return child


def _effective_limits(quota) -> tuple[int | None, int | None, list[str] | None]:
    """解析生效限额：未配置/None 的提问上限回退全局 TUTOR_DAILY_LIMIT。

    委托 ``domain.quota.resolve_quota_limits``，与 assistant/router._child_quota_decision
    共用同一份合并逻辑（ADR-0027：共享逻辑进 domain，避免两处重复）。
    """
    limits = resolve_quota_limits(quota, default_ask_limit=settings.TUTOR_DAILY_LIMIT)
    return limits.ask_limit, limits.minutes_limit, limits.allowed_subjects


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


# ───────── AI 使用管控（T10，家长配置/查询） ─────────
@router.get("/quota", response_model=TutorQuotaResp)
def get_quota(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> TutorQuotaResp:
    """查看某娃娃的 AI 使用管控配置。未配置时字段全为 None（走全局默认）。"""
    _own_child(session, parent, child_id)
    quota = get_tutor_quota(session=session, child_id=child_id)
    if quota is None:
        return TutorQuotaResp(child_id=child_id)
    return TutorQuotaResp(
        child_id=child_id,
        daily_ask_limit=quota.daily_ask_limit,
        daily_minutes_limit=quota.daily_minutes_limit,
        allowed_subjects=quota.allowed_subjects,
    )


@router.put("/quota", response_model=TutorQuotaResp)
def set_quota(
    *,
    session: SessionDep,
    parent: CurrentParent,
    child_id: UUID,
    payload: TutorQuotaUpdate,
) -> TutorQuotaResp:
    """设置某娃娃的 AI 使用管控（故事 23/26）。整体覆盖；None = 清除该项限制。"""
    _own_child(session, parent, child_id)
    error = validate_quota_config(
        daily_ask_limit=payload.daily_ask_limit,
        daily_minutes_limit=payload.daily_minutes_limit,
        allowed_subjects=payload.allowed_subjects,
    )
    if error is not None:
        raise HTTPException(status_code=422, detail=error)
    quota = upsert_tutor_quota(
        session=session,
        child_id=child_id,
        daily_ask_limit=payload.daily_ask_limit,
        daily_minutes_limit=payload.daily_minutes_limit,
        allowed_subjects=payload.allowed_subjects,
    )
    return TutorQuotaResp(
        child_id=child_id,
        daily_ask_limit=quota.daily_ask_limit,
        daily_minutes_limit=quota.daily_minutes_limit,
        allowed_subjects=quota.allowed_subjects,
    )


@router.get("/usage", response_model=TutorUsageResp)
def get_usage(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> TutorUsageResp:
    """查看某娃娃当日 AI 用量（次数/累计秒数），并回带生效限额。

    只读：无当日用量行时按 0 计（不在 GET 中建行）。
    """
    _own_child(session, parent, child_id)
    quota = get_tutor_quota(session=session, child_id=child_id)
    ask_limit, minutes_limit, allowed_subjects = _effective_limits(quota)
    usage = get_tutor_usage_today(session=session, child_id=child_id)
    asks = count_tutor_today(session=session, child_id=child_id)
    return TutorUsageResp(
        child_id=child_id,
        date=usage.usage_date if usage is not None else datetime.now(UTC).date(),
        asks_today=asks,
        used_seconds=usage.used_seconds if usage is not None else 0,
        ask_limit=ask_limit,
        minutes_limit=minutes_limit,
        allowed_subjects=allowed_subjects,
    )
