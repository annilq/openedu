"""Repository layer for the tutor (AI companion log) feature."""

import uuid

from sqlmodel import Session, select

from app.db.models import TutorLog


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
