"""流式 SSE 端点（ADR-0015 / 票据 08）：答疑逐字 + 出题逐张题卡。

- POST /api/v1/stream/tutor/ask      娃娃答疑流式（打字机）
- POST /api/v1/stream/tasks/generate  家长出题流式预览（题卡逐张浮现）

设计要点（忠诚 ADR-0015）：
  · 后端统一代理，安全层永不绕过：流前端 check_input，流后缓冲整体 check_output（决策 5）。
  · 用 Genkit 编排流式，但自行翻译为项目 SSE 信封（token/question/safety_refusal/done/error），
    不采用 serve_flow 原生格式，避免前端改解析。
  · 无真实引擎（mock 模式 / MODEL_FALLBACK=mock）→ 回退 MockProvider，保证闭环可跑。
"""
from __future__ import annotations

import json
import time

from fastapi import APIRouter, status
from fastapi.responses import StreamingResponse

from app.ai import (
    generate_questions_stream,
    resolve_engine,
    tutor_stream,
)
from app.api.deps import CurrentChild, CurrentParent, SessionDep
from app.core.config import settings
from app.core.errors import AppErrorException, ErrCode
from app.crud import (
    add_tutor_usage,
    count_tutor_today,
    create_tutor_log,
    get_tutor_quota,
    get_tutor_usage_today,
)
from app.domain import REASON_SUBJECT_SCOPE, build_provider, check_quota
from app.domain.safety import SAFE_REFUSAL, check_input, check_output
from app.models import TaskBatchCreate, TutorAskReq, User

router = APIRouter(prefix="/stream", tags=["stream"])


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _effective_limits(quota):  # type: ignore[no-untyped-def]
    ask_limit = settings.TUTOR_DAILY_LIMIT
    minutes_limit = None
    allowed_subjects = None
    if quota is not None:
        if quota.daily_ask_limit is not None:
            ask_limit = quota.daily_ask_limit
        minutes_limit = quota.daily_minutes_limit
        allowed_subjects = quota.allowed_subjects
    return ask_limit, minutes_limit, allowed_subjects


@router.post("/tutor/ask")
async def tutor_ask_stream(*, session: SessionDep, child: CurrentChild, payload: TutorAskReq):
    """娃娃答疑流式。先做配额/输入安全校验，再流式；流后整体校验才放量。"""
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
        async def _quota_refuse():  # type: ignore[no-untyped-def]
            yield _sse("error", {"message": decision.message})
        return StreamingResponse(_quota_refuse(), media_type="text/event-stream", status_code=code)

    combined = "\n".join(p for p in (payload.question, payload.knowledge_point, payload.context) if p)
    inp = check_input(combined)
    if not inp.safe:
        async def _refuse():  # type: ignore[no-untyped-def]
            yield _sse("safety_refusal", {"reason": inp.reason})
            yield _sse("done", {"usage": {"seconds": 0}})
        return StreamingResponse(_refuse(), media_type="text/event-stream")

    engine = resolve_engine(payload.model, parent_id=child.parent_id, session=session)
    started = time.perf_counter()

    async def _event_stream():  # type: ignore[no-untyped-def]
        tokens: list[str] = []
        try:
            if engine is None:
                raw = await build_provider().tutor(
                    grade=payload.grade,
                    subject=payload.subject,
                    knowledge_point=payload.knowledge_point,
                    context=payload.context,
                    question=payload.question,
                )
                tokens.append(raw)
            else:
                async for tok in tutor_stream(
                    engine,
                    grade=payload.grade,
                    subject=payload.subject,
                    knowledge_point=payload.knowledge_point,
                    context=payload.context,
                    question=payload.question,
                ):
                    tokens.append(tok)
        except Exception:
            yield _sse("error", {"message": "模型服务暂不可用，请稍后再试"})
            return

        full = "".join(tokens)
        if not check_output(full).safe:
            # 整体校验未过：不放量，发安全兜底
            yield _sse("safety_refusal", {"reason": "输出含敏感内容"})
            answer, blocked = SAFE_REFUSAL, True
        else:
            # 整体校验通过后才逐 token 放量（决策 5：不闪现违规片段）
            for tok in tokens:
                yield _sse("token", {"text": tok})
            answer, blocked = full, False

        elapsed = time.perf_counter() - started
        add_tutor_usage(session=session, child_id=child.id, seconds=elapsed)
        create_tutor_log(
            session=session,
            child_id=child.id,
            grade=payload.grade,
            subject=payload.subject,
            knowledge_point=payload.knowledge_point,
            question=payload.question,
            answer=answer,
            input_safe=True,
            output_safe=not blocked,
            blocked=blocked,
        )
        yield _sse("done", {"usage": {"seconds": round(elapsed, 3)}})

    return StreamingResponse(_event_stream(), media_type="text/event-stream")


@router.post("/tasks/generate")
async def tasks_generate_stream(*, session: SessionDep, parent: CurrentParent, payload: TaskBatchCreate):
    """家长出题流式预览（题卡逐张浮现）。不落库，供审阅；选定后走 batch-generate 持久化。"""
    if not payload.specs:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "生成规格 specs 不能为空")

    child_id = payload.child_id
    interests_pool = None
    if child_id is not None:
        child = session.get(User, child_id)
        if child is None or child.parent_id != parent.id:
            raise AppErrorException(ErrCode.TASK_CHILD_NOT_OWNED, "该娃娃不属于你的账号")
        from app.api.routes.tasks import _extract_interests_pool

        interests_pool = _extract_interests_pool(child)

    engine = resolve_engine(payload.model, parent_id=parent.id, session=session)
    focus = payload.focus_interest or []

    async def _event_stream():  # type: ignore[no-untyped-def]
        try:
            if engine is None:
                provider = build_provider()
                for i, sp in enumerate(payload.specs):
                    for _ in range(max(0, sp.count)):
                        f = focus[i % len(focus)] if focus else None
                        g = await provider.generate_question(
                            subject=sp.subject,
                            grade=sp.grade,
                            knowledge_point=sp.knowledge_point,
                            qtype=sp.qtype,
                            difficulty=sp.difficulty,
                            interests=interests_pool if f is None else None,
                            focus_interest=f,
                        )
                        yield _sse("question", g.__dict__)
            else:
                async for q in generate_questions_stream(
                    engine,
                    specs=list(payload.specs),
                    interests=interests_pool,
                    focus_interests=focus,
                ):
                    yield _sse("question", q.model_dump())
        except Exception:
            yield _sse("error", {"message": "模型服务暂不可用，请稍后再试"})
            return
        yield _sse("done", {"usage": {"seconds": 0}})

    return StreamingResponse(_event_stream(), media_type="text/event-stream")
