"""教师端 AI 伴学答疑日志（F-305）。

保留教师侧「日志可观测」端点（非 AI 生成，故不并入 /api/v1/assistant/chat）：
- GET  /tutor/logs   查看某学生的 AI 答疑日志

学生端实时答疑已统一收敛到 ``POST /api/v1/assistant/chat``（role=student → 伴学答疑），
原 ``POST /tutor/ask`` 已废弃。每日配额管控（TutorQuota/TutorUsage）已移除。
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter

from app.core.deps import CurrentTeacher, SessionDep
from app.core.errors import ErrCode
from app.core.guard import require_owned_student
from app.db.models import User
from app.features.tutor.repository import list_tutor_logs
from app.features.tutor.schemas import TutorLogResp

router = APIRouter(prefix="/tutor", tags=["tutor"])


def _own_student(session, teacher, student_id: UUID) -> User:
    """校验 student 归属当前教师，返回学生；不存在/越权 → 403。

    判定本身委托 ``core.guard``，这里只保留「本端点对外暴露 403 + 该文案」的契约。
    """
    return require_owned_student(
        session=session,
        owner_id=teacher.id,
        student_id=student_id,
        code=ErrCode.FORBIDDEN,
        message="Not your student",
    )


@router.get("/logs", response_model=list[TutorLogResp])
def logs(
    *, session: SessionDep, teacher: CurrentTeacher, student_id: UUID
) -> list[TutorLogResp]:
    """教师查看某学生的 AI 答疑日志（F-305）。越权（非本教师学生）→ 403。"""
    student = _own_student(session, teacher, student_id)
    rows = list_tutor_logs(session=session, student_id=student.id)
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
