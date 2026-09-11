"""悬浮助手业务编排（ADR-0024 / 0025 / 0026）：把「流 → 落地」整条编排收口到 service 层。

路由器端点（``router.py``）只负责鉴权 / 入参校验 / 包 ``StreamingResponse``，不含任何 ORM
与编排逻辑。本模块持有：角色解析、subject 探测、RuntimeDeps 构造、预路由配额判定、会话
upsert、事件流折叠为持久化（Message 轨迹 + TutorLog 副作用）。

``runtime`` 以可选参数注入（默认 ``get_runtime()`` 单例），便于单测用桩 ``AgentRuntime``
替换，无需真实 ``discover()`` 与 HTTP 链路（见 ``tests/features/assistant/test_service.py``）。
"""
from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any
from uuid import UUID, uuid4

from agent_core.ports import RuntimeDeps
from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_ERROR,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
    AssistantEvent,
)
from agent_core.runtime import AgentRuntime
from agent_core.runtime_singleton import get_runtime
from agent_core.subagent import SubAgentContext
from app.ai.engine import resolve_engine
from app.ai.subagents.tutor.agent import detect_subject
from app.core.config import settings
from app.core.errors import AppErrorException, ErrCode
from app.db.models import Conversation, Message
from app.domain import (
    REASON_SUBJECT_SCOPE,
    build_provider,
    build_retriever,
    check_quota,
    resolve_quota_limits,
)
from app.domain.safety import ChildSafety
from app.features.assistant.repository import (
    get_conversation_by_id,
    load_chat_history,
    next_turn,
)
from app.features.assistant.schemas import AssistantChatReq
from app.features.tutor.repository import (
    count_tutor_today,
    create_tutor_log,
    get_tutor_quota,
    get_tutor_usage_today,
)


def _child_quota_decision(session: Any, child_id: UUID, subject: str):
    """复用 T10 配额逻辑（F-305 合规前置）。

    生效限额（全局默认 + 每娃覆盖合并）委托 ``domain.quota.resolve_quota_limits``，
    消除与 tutor/router._effective_limits 的重复逻辑（ADR-0027：共享逻辑进 domain）。
    """
    quota = get_tutor_quota(session=session, child_id=child_id)
    limits = resolve_quota_limits(quota, default_ask_limit=settings.TUTOR_DAILY_LIMIT)
    usage = get_tutor_usage_today(session=session, child_id=child_id)
    used_seconds = usage.used_seconds if usage is not None else 0
    used = count_tutor_today(session=session, child_id=child_id)
    return check_quota(
        subject=subject,
        asks_today=used,
        used_seconds=used_seconds,
        ask_limit=limits.ask_limit,
        minutes_limit=limits.minutes_limit,
        allowed_subjects=limits.allowed_subjects,
    )


async def chat(
    *,
    caller: Any,
    req: AssistantChatReq,
    session: Any,
    runtime: AgentRuntime | None = None,
) -> AsyncIterator[str]:
    """悬浮助手对话编排：预路由 → 配额 → 会话 upsert → 运行事件流 → 折叠持久化。

    返回 SSE 帧的异步迭代器；持久化作为副作用在迭代 / finally 中发生。HTTP 关注点
    （``StreamingResponse`` 包装、空消息校验）留在 ``router``，本函数不感知。
    """
    rt = runtime or get_runtime()
    message = (req.message or "").strip()

    role = caller.role
    if role == "child":
        child_id = caller.user.id
        parent_id = caller.user.parent_id
    else:  # parent
        parent_id = caller.user.id
        child_id = None

    # subject 为教育特有概念，由端点计算并透传（agent_core 的 RouteDecision 不感知业务语义）。
    subject = detect_subject(message)

    # 构建运行时依赖（seam 注入）：provider 走单一解析链；retriever 默认 mock；
    # 儿童端注入输入安全闸门（首层防御），家长端不拦截。
    engine = (
        resolve_engine(req.model, parent_id=parent_id, session=session)
        if parent_id is not None
        else None
    )
    provider = build_provider(engine=engine)
    retriever = build_retriever()
    safety = ChildSafety() if role == "child" else None
    deps = RuntimeDeps(provider=provider, retriever=retriever, safety=safety)

    # 预路由：解析 business（不流式），供配额判定与落库复用，消除端点对 THINKING(extra) 隐式契约。
    decision = await rt.decide(message, role=role, deps=deps)

    if role == "child" and decision.business is not None:
        # 使用配额（伴学答疑计入每日上限）；subject 取自预路由决策，仅算一次。
        # 关键：输入不安全时 runtime.decide 已把 business 置 None（run 内直接拒绝），
        # 故业务未路由成功时不计配额——否则会先抛「配额超限」而非安全拒绝。
        quota_decision = _child_quota_decision(session, child_id, subject)  # type: ignore[arg-type]
        if not quota_decision.allowed:
            code = ErrCode.TUTOR_QUOTA_EXCEEDED
            if quota_decision.code == REASON_SUBJECT_SCOPE:
                code = ErrCode.TUTOR_SUBJECT_FORBIDDEN
            raise AppErrorException(code, quota_decision.message)

    # ── 会话持久化（复用 Conversation/Message，ADR-0026 多轮） ──
    # 优先按 session_id 续接已有会话并载入历史；否则新建。
    conversation: Conversation | None = None
    conv_id: UUID | None = None
    history: list[dict] | None = None

    if req.session_id:
        try:
            existing = get_conversation_by_id(session, UUID(req.session_id))
        except (ValueError, AttributeError):
            existing = None
        if (
            existing is not None
            and existing.parent_id == parent_id
            and existing.child_id == child_id
        ):
            # 归属校验通过：续接该会话，载入历史拼入 prompt
            conversation = existing
            conv_id = existing.id
            conversation.status = "running"
            history = load_chat_history(session, conv_id)
            session.add(
                Message(
                    conversation_id=conv_id,
                    turn=next_turn(session, conv_id),
                    role="user",
                    step="input",
                    content=message,
                )
            )
            session.commit()

    if conversation is None:
        conv_id = uuid4()
        conversation = Conversation(
            id=conv_id,
            kind=decision.business or "agent",  # 路由决策显式给出，不再依赖 THINKING(extra)
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
        # 无 session_id：兼容客户端自带历史（兜底）
        history = req.history

    # 业务字段经 ctx.extra 透传（agent_core 不感知任何教育语义）。
    ctx = SubAgentContext(
        role=role,
        message=message,
        history=history,
        model=req.model,
        skills="",  # runtime 会按 manifest 注入 skill_prompt
        extra={
            "subject": subject,
            "parent_id": parent_id,
            "child_id": child_id,
            "grade": (caller.user.grade if role == "child" else 0) or 0,
            "focus_interest": req.focus_interest,
            "session_id": str(conv_id),
        },
    )

    async def event_stream() -> AsyncIterator[str]:
        final_text = ""
        cards: list[dict] = []
        tool_msgs: list[Message] = []
        conv_status = "done"
        turn = 1
        blocked_flag = False

        # 复用预航班决策（decision），避免重复路由；run 返回事件流。
        stream: AsyncIterator[AssistantEvent] = rt.run(
            message,
            role=role,
            ctx=ctx,
            deps=deps,
            business=decision.business,
            session=session,
        )

        # 路由步落库：用结构化决策，去掉 THINKING(extra.business) 隐式契约
        if decision.business is not None:
            session.add(
                Message(
                    conversation_id=conv_id,
                    turn=turn,
                    role="system",
                    step="routing",
                    content=decision.name or decision.business,
                )
            )
            turn += 1

        try:
            async for ev in stream:
                # 持久化（边流边记）
                if ev.eventType == EVENT_TOOL_CALL:
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
                    # DATA 事件 data 载荷为 {type, result}；落库保留 result 本体
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
            if role == "child" and decision.business == "tutor":
                try:
                    create_tutor_log(
                        session=session,
                        child_id=child_id,
                        grade=caller.user.grade or 0,
                        subject=subject,
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

    return event_stream()
