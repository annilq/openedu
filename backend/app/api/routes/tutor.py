from uuid import UUID

from fastapi import APIRouter, HTTPException, status

from app.api.deps import CurrentChild, CurrentParent, SessionDep
from app.core.config import settings
from app.crud import count_tutor_today, create_tutor_log, list_tutor_logs
from app.domain import TutorService, build_provider
from app.models import TutorAnswer, TutorAskReq, TutorLogResp, User

router = APIRouter(prefix="/tutor", tags=["tutor"])


@router.post("/ask", response_model=TutorAnswer)
def ask(
    *, session: SessionDep, child: CurrentChild, payload: TutorAskReq
) -> TutorAnswer:
    """娃娃自由提问，AI 给出适龄讲解（F-302）。

    内容安全（F-304）：输入越狱/非学习类主题、输出敏感词均拦截并返回安全兜底；
    日志落库（F-305）。每日上限由 TUTOR_DAILY_LIMIT 控制（达上限 429）。
    """
    used = count_tutor_today(session=session, child_id=child.id)
    if used >= settings.TUTOR_DAILY_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"今日 AI 答疑次数已达上限（{settings.TUTOR_DAILY_LIMIT} 次），"
                "明天再来哦～"
            ),
        )

    service = TutorService(build_provider())
    result = service.explain(
        grade=payload.grade,
        subject=payload.subject,
        knowledge_point=payload.knowledge_point,
        context=payload.context,
        question=payload.question,
    )

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
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise HTTPException(status_code=403, detail="Not your child")
    rows = list_tutor_logs(session=session, child_id=child_id)
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
