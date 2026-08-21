import time
from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, status

from app.api.deps import CurrentChild, CurrentParent, SessionDep
from app.core.config import settings
from app.crud import (
    add_tutor_usage,
    count_tutor_today,
    create_tutor_log,
    get_tutor_quota,
    get_tutor_usage_today,
    list_tutor_logs,
    upsert_tutor_quota,
)
from app.domain import (
    REASON_SUBJECT_SCOPE,
    TutorService,
    build_provider,
    build_retriever,
    check_quota,
    validate_quota_config,
)
from app.models import (
    TutorAnswer,
    TutorAskReq,
    TutorLogResp,
    TutorQuotaResp,
    TutorQuotaUpdate,
    TutorUsageResp,
    User,
)

router = APIRouter(prefix="/tutor", tags=["tutor"])


def _own_child(session, parent, child_id: UUID) -> User:
    """校验 child 归属当前家长，返回娃娃；不存在/越权 → 403。"""
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise HTTPException(status_code=403, detail="Not your child")
    return child


def _effective_limits(quota) -> tuple[int | None, int | None, list[str] | None]:
    """解析生效限额：未配置/None 的提问上限回退全局 TUTOR_DAILY_LIMIT。"""
    ask_limit = settings.TUTOR_DAILY_LIMIT
    minutes_limit = None
    allowed_subjects = None
    if quota is not None:
        if quota.daily_ask_limit is not None:
            ask_limit = quota.daily_ask_limit
        minutes_limit = quota.daily_minutes_limit
        allowed_subjects = quota.allowed_subjects
    return ask_limit, minutes_limit, allowed_subjects


@router.post("/ask", response_model=TutorAnswer)
def ask(
    *, session: SessionDep, child: CurrentChild, payload: TutorAskReq
) -> TutorAnswer:
    """娃娃自由提问，AI 给出适龄讲解（F-302）。

    内容安全（F-304）：输入越狱/非学习类主题、输出敏感词均拦截并返回安全兜底；
    日志落库（F-305）。
    使用管控（T10，故事 23/26）：答疑前校验 学科范围 / 每日次数 / 每日时长，
    越界 403、超额 429；答疑后累计当日耗时秒数。

    备注：次数校验（读 count）与日志落库（写）非同一原子事务，极端并发下
    可能多放行 1~N 次——单娃低频场景可接受，见技术架构 §10 技术债。
    被安全拦截（blocked）的请求也计次并累计耗时：防探测刷库，且输出拦截
    实际已调用模型。
    """
    quota = get_tutor_quota(session=session, child_id=child.id)
    ask_limit, minutes_limit, allowed_subjects = _effective_limits(quota)
    usage = get_tutor_usage_today(session=session, child_id=child.id)
    used_seconds = usage.used_seconds if usage is not None else 0
    used = count_tutor_today(session=session, child_id=child.id)

    decision = check_quota(
        subject=payload.subject.strip(),
        asks_today=used,
        used_seconds=used_seconds,
        ask_limit=ask_limit,
        minutes_limit=minutes_limit,
        allowed_subjects=allowed_subjects,
    )
    if not decision.allowed:
        code = status.HTTP_429_TOO_MANY_REQUESTS
        if decision.code == REASON_SUBJECT_SCOPE:
            code = status.HTTP_403_FORBIDDEN
        raise HTTPException(status_code=code, detail=decision.message)

    service = TutorService(build_provider(), build_retriever())
    started = time.perf_counter()
    result = service.explain(
        grade=payload.grade,
        subject=payload.subject,
        knowledge_point=payload.knowledge_point,
        context=payload.context,
        question=payload.question,
    )
    elapsed = time.perf_counter() - started

    # 耗时与次数分开累计：次数口径在 TutorLog 落库后即时生效（下面 create_tutor_log）
    add_tutor_usage(session=session, child_id=child.id, seconds=elapsed)
    create_tutor_log(
        session=session,
        child_id=child.id,
        grade=payload.grade,
        subject=payload.subject,
        knowledge_point=payload.knowledge_point,
        question=payload.question,
        answer=result.answer,
        input_safe=result.input_safe,
        output_safe=result.output_safe,
        blocked=result.blocked,
    )

    return TutorAnswer(
        answer=result.answer, blocked=result.blocked, reason=result.reason
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
