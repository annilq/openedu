"""悬浮助手统一端点（ADR-0024 / 0025 / 0026）：所有 AI 功能经此单入口。

``POST /api/v1/assistant/chat`` 接收自由文本 + 角色身份，经 AgentRuntime 路由到
对应 SubAgent，以 SSE 流式推送 AG-UI 事件帧（USER_MESSAGE / THINKING / TOOL_CALL /
TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE）。

- 双端通用：家长与孩子共用此端点（Caller 依赖解析角色）。
- 娃娃端角色感知 + 输入安全 + 使用配额（ADR-008 / T10）；家长端可出题/查任务/伴学。
- 会话持久化复用 ``Conversation`` / ``Message``（ADR-0022 升级为助手会话，supersede）。

废弃的旧 AI 端点（统一收敛到此）：``/ai/tutor/ask``、``/ai/tasks/generate``、``/tutor/ask``。
"""
from __future__ import annotations

from typing import AsyncIterator
from uuid import uuid4

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlmodel import Field, Session, SQLModel

from app.ai.runtime import AgentRuntime
from app.ai.runtime.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_ERROR,
    EVENT_THINKING,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
)
from app.ai.subagents.tutor import detect_subject
from app.core.config import settings
from app.core.deps import CallerDep, SessionDep
from app.db.models import Conversation, Message
from app.domain import REASON_SUBJECT_SCOPE, check_quota
from app.features.tutor.repository import (
    count_tutor_today,
    create_tutor_log,
    get_tutor_quota,
    get_tutor_usage_today,
)

router = APIRouter(prefix="/assistant", tags=["assistant"])


class AssistantChatReq(SQLModel):
    """悬浮助手对话请求体。

    WF-4 兴趣题模式：``focus_interest`` 为显式聚焦主题（如「恐龙」「太空」），
    经 runtime 透传给出题 SubAgent，注入出题 prompt 让情境围绕该主题展开。
    """

    message: str = Field(min_length=1, max_length=2000)
    session_id: str | None = None
    model: str | None = None
    history: list[dict] | None = None
    focus_interest: str | None = None


# ── Runtime 单例（文件夹发现仅一次） ──
_RUNTIME: AgentRuntime | None = None


def _get_runtime() -> AgentRuntime:
    global _RUNTIME
    if _RUNTIME is None:
        _RUNTIME = AgentRuntime.discover()
    return _RUNTIME


def _child_quota_decision(session: Session, child_id, subject: str):
    """复用 T10 配额逻辑（F-305 合规前置）。"""
    quota = get_tutor_quota(session=session, child_id=child_id)
    ask_limit: int | None = settings.TUTOR_DAILY_LIMIT
    minutes_limit: int | None = None
    allowed_subjects: list[str] | None = None
    if quota is not None:
        if quota.daily_ask_limit is not None:
            ask_limit = quota.daily_ask_limit
        minutes_limit = quota.daily_minutes_limit
        allowed_subjects = quota.allowed_subjects
    usage = get_tutor_usage_today(session=session, child_id=child_id)
    used_seconds = usage.used_seconds if usage is not None else 0
    used = count_tutor_today(session=session, child_id=child_id)
    return check_quota(
        subject=subject,
        asks_today=used,
        used_seconds=used_seconds,
        ask_limit=ask_limit,
        minutes_limit=minutes_limit,
        allowed_subjects=allowed_subjects,
    )


@router.post("/chat")
async def assistant_chat(req: AssistantChatReq, caller: CallerDep, session: SessionDep) -> StreamingResponse:
    """悬浮助手对话：SSE 流式返回 AG-UI 事件。"""
    message = (req.message or "").strip()
    if not message:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="消息不能为空")

    role = caller.role
    if role == "child":
        child_id = caller.user.id
        parent_id = caller.user.parent_id
        # 使用配额（伴学答疑计入每日上限）
        decision = _child_quota_decision(session, child_id, detect_subject(message))
        if not decision.allowed:
            code = status.HTTP_429_TOO_MANY_REQUESTS
            if decision.code == REASON_SUBJECT_SCOPE:
                code = status.HTTP_403_FORBIDDEN
            raise HTTPException(status_code=code, detail=decision.message)
    else:  # parent
        parent_id = caller.user.id
        child_id = None

    # ── 会话持久化（复用 Conversation/Message，ADR-0026） ──
    conv_id = uuid4()
    conversation = Conversation(
        id=conv_id,
        kind="agent",  # run 内 THINKING(routing) 帧会更新为具体 business
        parent_id=parent_id,
        child_id=child_id,
        model=req.model,
        status="running",
    )
    session.add(conversation)
    session.add(
        Message(conversation_id=conv_id, turn=0, role="user", step="input", content=message)
    )
    session.commit()

    runtime = _get_runtime()

    async def event_stream() -> AsyncIterator[str]:
        final_text = ""
        cards: list[dict] = []
        tool_msgs: list[Message] = []
        conv_status = "done"
        turn = 1
        routed_business: str | None = None
        blocked_flag = False

        try:
            async for ev in runtime.run(
                message,
                role=role,
                child_id=child_id,
                parent_id=parent_id,
                session=session,
                model=req.model,
                session_id=str(conv_id),
                history=req.history,
                focus_interest=req.focus_interest,
            ):
                # 持久化（边流边记）
                if ev.eventType == EVENT_THINKING and ev.extra.get("business"):
                    conversation.kind = ev.extra["business"]
                    routed_business = ev.extra["business"]
                    session.add(
                        Message(
                            conversation_id=conv_id,
                            turn=turn,
                            role="system",
                            step="routing",
                            content=ev.extra.get("name", ev.extra["business"]),
                        )
                    )
                    turn += 1
                elif ev.eventType == EVENT_TOOL_CALL:
                    tool_msgs.append(
                        Message(
                            conversation_id=conv_id,
                            turn=turn,
                            role="tool",
                            step="tool_call",
                            content=ev.label or ev.tool or "",
                            payload=ev.args,
                        )
                    )
                    turn += 1
                elif ev.eventType == EVENT_TOOL_RESULT:
                    tool_msgs.append(
                        Message(
                            conversation_id=conv_id,
                            turn=turn,
                            role="tool",
                            step="tool_result",
                            content=ev.tool or "",
                            payload={"result": ev.result},
                        )
                    )
                    turn += 1
                elif ev.eventType == EVENT_ASSISTANT_MESSAGE and ev.text:
                    final_text += ev.text
                elif ev.eventType == EVENT_DATA and ev.data:
                    # DATA 事件 data 载荷为 {status, type, result}；落库保留 result 本体
                    cards.append(ev.data.get("result", ev.data))
                elif ev.eventType == EVENT_ERROR:
                    conv_status = "error"
                    if ev.code == "INPUT_UNSAFE":
                        blocked_flag = True
                    if ev.message:
                        final_text = ev.message

                yield ev.to_sse()
        finally:
            # 收尾落库：工具步骤 + 助手输出 + 会话状态
            for m in tool_msgs:
                session.add(m)
            if final_text or cards:
                session.add(
                    Message(
                        conversation_id=conv_id,
                        turn=turn,
                        role="assistant",
                        step="output",
                        content=final_text,
                        payload={"cards": cards} if cards else None,
                    )
                )
            conversation.status = conv_status

            # ADR-008：娃娃端伴学交互落 TutorLog（家长可见 + 每日上限计数，F-304/305）
            if role == "child" and routed_business == "tutor":
                try:
                    _subject = detect_subject(message)
                    create_tutor_log(
                        session=session,
                        child_id=child_id,
                        grade=caller.user.grade or 0,
                        subject=_subject or "",
                        knowledge_point="",
                        question=message,
                        answer=final_text,
                        input_safe=not blocked_flag,
                        output_safe=True,
                        blocked=blocked_flag,
                    )
                except Exception:
                    # 落库失败不应破坏已流的响应
                    pass

            session.commit()

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
