"""悬浮助手业务编排（ADR-0024 / 0025 / 0026）：把「流 → 落地」整条编排收口到 service 层。

路由器端点（``router.py``）只负责鉴权 / 入参校验 / 包 ``StreamingResponse``，不含任何 ORM
与编排逻辑。本模块持有：角色解析、subject 探测、RuntimeDeps 构造、会话 upsert、事件流
折叠为持久化（Message 轨迹 + TutorLog 副作用）。

ADR-0048 起还持有**会话历史的读编排**（列表 / 回放）：端点只做 HTTP 适配，三次查询的
归并（会话 × 元信息 × 娃娃名）在这一层。

``runtime`` 以可选参数注入（默认 ``get_runtime()`` 单例），便于单测用桩 ``AgentRuntime``
替换，无需真实 ``discover()`` 与 HTTP 链路（见 ``tests/features/assistant/test_service.py``）。
"""
from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any
from uuid import UUID, uuid4

from agent_core.ports import RuntimeDeps, TextDelta
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
from app.db.models import Conversation, Message, get_datetime_utc
from app.domain import build_provider, build_retriever
from app.domain.safety import ChildSafety
from app.features.assistant.repository import (
    child_names,
    conversation_meta,
    derive_title,
    get_conversation_by_id,
    list_chat_conversations,
    load_chat_history_with_summary,
    next_turn,
    read_conversation_bubbles,
    title_of,
)
from app.features.assistant.repository import (
    delete_conversations as repo_delete_conversations,
)
from app.features.assistant.schemas import (
    AssistantBubbleResp,
    AssistantChatReq,
    AssistantConversationDetailResp,
    AssistantConversationResp,
)
from app.features.tutor.repository import create_tutor_log

# 自动摘要（P2）：compaction 命中预算要丢轮次时，把最旧轮次压成一句摘要注入，
# 而非直接丢弃，保留长对话的上下文连续性。
_SUMMARY_SYSTEM = (
    "你是对话摘要器。把下面多轮学习对话压缩成一句中文摘要（不超过 80 字），"
    "保留关键事实：学生问了什么、做了什么题、结论或订正要点。"
    "不要编造，不要复述原文。"
)


async def _summarize_dropped(provider, dropped: list[dict]) -> str | None:
    """把被 compaction 丢弃的最旧轮次压缩成一句摘要；失败返回 None 回退纯丢弃。"""
    if not dropped:
        return None
    lines = "\n".join(
        f"{'学生' if m.get('role') == 'user' else '老师'}: {m.get('content', '')}"
        for m in dropped
    )
    parts: list[str] = []
    try:
        async for ev in provider.stream(_SUMMARY_SYSTEM, f"【对话历史】\n{lines}"):
            if isinstance(ev, TextDelta):
                parts.append(ev.delta)
    except Exception:
        return None
    text = "".join(parts).strip()
    return text or None


async def chat(
    *,
    caller: Any,
    req: AssistantChatReq,
    session: Any,
    runtime: AgentRuntime | None = None,
) -> AsyncIterator[str]:
    """悬浮助手对话编排：预路由 → 会话 upsert → 运行事件流 → 折叠持久化。

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

    # 预路由：解析 business（不流式），供落库复用，消除端点对 THINKING(extra) 隐式契约。
    decision = await rt.decide(message, role=role, deps=deps)

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
            # 自动摘要（P2）：compaction 需丢最旧轮次时复用本次 provider 压成摘要注入，
            # 失败则回退纯丢弃——不额外构造 provider、不阻断主链路。
            history = await load_chat_history_with_summary(
                session,
                conv_id,
                summarize=lambda dropped: _summarize_dropped(provider, dropped),
            )
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
            # 会话名取首条用户消息截断（ADR-0048）：它同时是会话列表的行名。
            # 写入点唯一（会话只在这里建立），值天然稳定——首条消息不会变。
            title=derive_title(message),
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
        # turn 起点必须接着该会话已有的序号往后排，**不能写死 1**：本生成器每轮都会
        # 重新进入，续接轮的 routing / tool / output 会与第一轮撞号（user 消息用的是
        # ``next_turn``，两者不同源）。`_read_history` 按 turn 升序读 → 第二轮的回答
        # 排到第二轮的提问之前，模型拿到的是倒置的上下文。
        turn = next_turn(session, conv_id)
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
                    # DATA 帧整帧落库：`{type(判别键), result(载荷)}` 一起存。
                    # 只存 result 会丢掉种类——与前端 fold 丢弃 `data.type` 是同一类
                    # 缺陷（ADR-0042）：落库的 payload 必须自描述，否则将来做历史回放
                    # 时无法把卡片分派回正确的渲染器。
                    cards.append(ev.data)
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
            # 最近活动时间：会话列表按它倒序（刚被续接的旧会话应浮到最上面）。
            # `updated_at` 的 default_factory 只在**构造**时求值，不会随写入自动刷新，
            # 不显式赋值它就跟 created_at 一样是死字段。
            conversation.updated_at = get_datetime_utc()

            # ADR-008：娃娃端伴学交互落 TutorLog（家长可见，F-305）
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


# ── 会话历史读编排（用户面，ADR-0048） ────────────────────────────────────────
#
# 与「运行轨迹」调试端点（``/api/v1/ai/debug/conversations``）刻意分开：那边返回全部
# step 与原始 payload，供审计与排障；这边只返回对话气泡与列表元信息。两者读同一批行，
# 但形状不同——合并会同时伤害两个消费者（用户面被迫拖走工具原始载荷，审计侧丢掉保真度）。


def _summary_of(
    conv: Conversation,
    *,
    first_user: str,
    child_name: str | None,
    bubble_count: int,
) -> AssistantConversationResp:
    """ORM 行 → 列表行契约（title 的回落规则收口在 ``repository.title_of``）。"""
    return AssistantConversationResp(
        id=conv.id,
        title=title_of(conv, first_user),
        kind=conv.kind,
        child_id=conv.child_id,
        child_name=child_name,
        bubble_count=bubble_count,
        created_at=conv.created_at,
        updated_at=conv.updated_at,
    )


def list_conversations(
    *, session: Any, parent_id: UUID, limit: int = 50
) -> list[AssistantConversationResp]:
    """家长的历史会话列表（含名下娃娃的），最近活动倒序。

    「我的 / 孩子的」不在这里分段：分段是展示层决策（ADR-0048 选了按娃分两段），
    服务端只保证每行带够判别信息（``child_id`` → 是否可续接，``child_name`` → 归属标签）。
    """
    convs = list_chat_conversations(session=session, parent_id=parent_id, limit=limit)
    meta = conversation_meta(session, [c.id for c in convs])
    names = child_names(session, [c.child_id for c in convs if c.child_id])
    out: list[AssistantConversationResp] = []
    for conv in convs:
        m = meta.get(conv.id, {})
        out.append(
            _summary_of(
                conv,
                first_user=m.get("first_user", ""),
                child_name=names.get(conv.child_id) if conv.child_id else None,
                bubble_count=m.get("bubble_count", 0),
            )
        )
    return out


def conversation_detail(
    *, session: Any, conv: Conversation
) -> AssistantConversationDetailResp:
    """一次会话的概要 + 全部气泡。

    只读回放（孩子的会话）与恢复续接（家长自己的会话）拿的是**同一份载荷**：
    两者只在「加载后能不能继续发消息」上有区别，那是前端的模式状态，不是两种数据。
    """
    bubbles = [
        AssistantBubbleResp(**b) for b in read_conversation_bubbles(session, conv.id)
    ]
    first_user = next((b.text for b in bubbles if b.role == "user"), "")
    names = child_names(session, [conv.child_id] if conv.child_id else [])
    return AssistantConversationDetailResp(
        conversation=_summary_of(
            conv,
            first_user=first_user,
            child_name=names.get(conv.child_id) if conv.child_id else None,
            bubble_count=len(bubbles),
        ),
        bubbles=bubbles,
    )


def delete_conversations(
    *, session: Any, parent_id: UUID, ids: list[UUID]
) -> int:
    """批量删除本家长名下的会话及其消息（多选删除，ADR-0048 补充）。

    归属校验与消息级联删除都收口在 repository（与读路径同一份可见轮次判定相反，
    这里只做「按 id + parent_id 删干净」）。返回实际删掉的会话条数。
    """
    return repo_delete_conversations(
        session=session, parent_id=parent_id, ids=ids
    )
