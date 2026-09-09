"""Repository layer for the tutor (AI governance) feature."""

import math
import uuid
from datetime import UTC, date, datetime

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, func, select, update

from app.db.models import TutorLog, TutorQuota, TutorUsage


def create_tutor_log(
    *,
    session: Session,
    child_id: uuid.UUID,
    grade: int,
    subject: str,
    knowledge_point: str,
    question: str,
    answer: str,
    input_safe: bool,
    output_safe: bool,
    blocked: bool,
) -> TutorLog:
    log = TutorLog(
        child_id=child_id,
        grade=grade,
        subject=subject,
        knowledge_point=knowledge_point,
        question=question,
        answer=answer,
        input_safe=input_safe,
        output_safe=output_safe,
        blocked=blocked,
    )
    session.add(log)
    session.commit()
    session.refresh(log)
    return log


def count_tutor_today(*, session: Session, child_id: uuid.UUID) -> int:
    """当日已使用的 AI 答疑次数（F-304 每日上限判定）。"""
    today = datetime.now(UTC).date()
    return session.exec(
        select(func.count(TutorLog.id)).where(
            TutorLog.child_id == child_id,
            func.date(TutorLog.created_at) == today.isoformat(),
        )
    ).one()


def list_tutor_logs(
    *, session: Session, child_id: uuid.UUID, limit: int = 200
) -> list[TutorLog]:
    """按时间倒序返回某娃娃的 AI 答疑日志（家长端查看）。"""
    return session.exec(
        select(TutorLog)
        .where(TutorLog.child_id == child_id)
        .order_by(TutorLog.created_at.desc())
        .limit(limit)
    ).all()


def get_tutor_quota(*, session: Session, child_id: uuid.UUID) -> TutorQuota | None:
    """读取某娃娃的 AI 使用管控配置（未配置返回 None，走全局默认）。"""
    return session.exec(
        select(TutorQuota).where(TutorQuota.child_id == child_id)
    ).first()


def upsert_tutor_quota(
    *,
    session: Session,
    child_id: uuid.UUID,
    daily_ask_limit: int | None,
    daily_minutes_limit: int | None,
    allowed_subjects: list[str] | None,
) -> TutorQuota:
    """写入/更新某娃娃的管控配置（每娃一条，整体覆盖）。"""
    quota = get_tutor_quota(session=session, child_id=child_id)
    if quota is None:
        quota = TutorQuota(child_id=child_id)
    quota.daily_ask_limit = daily_ask_limit
    quota.daily_minutes_limit = daily_minutes_limit
    quota.allowed_subjects = allowed_subjects
    quota.updated_at = datetime.now(UTC)
    session.add(quota)
    session.commit()
    session.refresh(quota)
    return quota


def _today_usage(
    session: Session, child_id: uuid.UUID, today: date
) -> TutorUsage | None:
    return session.exec(
        select(TutorUsage).where(
            TutorUsage.child_id == child_id,
            TutorUsage.usage_date == today,
        )
    ).first()


def get_tutor_usage_today(
    *, session: Session, child_id: uuid.UUID
) -> TutorUsage | None:
    """只读取当日用量行（GET 接口用，无写副作用）；无则 None。"""
    return _today_usage(session, child_id, datetime.now(UTC).date())


def get_or_create_tutor_usage(
    *, session: Session, child_id: uuid.UUID
) -> TutorUsage:
    """取当日用量行（不存在则建，used_seconds=0）。

    并发首问时另一请求可能已抢先建行：捕获唯一约束冲突回滚后重查，
    而不是让请求 500。
    """
    today = datetime.now(UTC).date()
    usage = _today_usage(session, child_id, today)
    if usage is None:
        usage = TutorUsage(child_id=child_id, usage_date=today, used_seconds=0)
        session.add(usage)
        try:
            session.commit()
        except IntegrityError:
            session.rollback()
            usage = _today_usage(session, child_id, today)
            if usage is None:  # 理论不可达：冲突后行必存在
                raise
        else:
            session.refresh(usage)
    return usage


def add_tutor_usage(
    *, session: Session, child_id: uuid.UUID, seconds: float
) -> None:
    """答疑完成后累计当日耗时（秒，向上取整避免瞬时调用永远记 0）。

    用 SQL 原子自增（used_seconds = used_seconds + n），避免并发下读-改-写丢更新。
    """
    today = datetime.now(UTC).date()
    get_or_create_tutor_usage(session=session, child_id=child_id)
    session.execute(
        update(TutorUsage)
        .where(
            TutorUsage.child_id == child_id,
            TutorUsage.usage_date == today,
        )
        .values(used_seconds=TutorUsage.used_seconds + max(0, math.ceil(seconds)))
    )
    session.commit()
