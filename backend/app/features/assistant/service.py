"""悬浮助手业务编排（ADR-0024 / 0025 / 0026）：把「流 → 落地」整条编排收口到 service 层。

路由器端点（``router.py``）只负责鉴权 / 入参校验 / 包 ``StreamingResponse``，不含任何 ORM
与编排逻辑。本模块持有：角色解析、subject 探测、RuntimeDeps 构造、会话 upsert、事件流
折叠为持久化（Message 轨迹 + TutorLog 副作用）。

ADR-0048 起还持有**会话历史的读编排**（列表 / 回放）：端点只做 HTTP 适配，三次查询的
归并（会话 × 元信息 × 学生名）在这一层。

``runtime`` 以可选参数注入（默认 ``get_runtime()`` 单例），便于单测用桩 ``AgentRuntime``
替换，无需真实 ``discover()`` 与 HTTP 链路（见 ``tests/features/assistant/test_service.py``）。
"""
from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from typing import Any
from uuid import UUID, uuid4

from agent_core import IntentSignal
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
from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned
from app.db.models import Class, Conversation, Message, Role, get_datetime_utc
from app.db.models.material import KnowledgePoint
from app.domain import build_provider, build_retriever
from app.domain.safety import StudentSafety
from app.features.assistant.repository import (
    conversation_meta,
    derive_title,
    get_conversation_by_id,
    list_chat_conversations,
    load_chat_history_with_summary,
    next_turn,
    read_conversation_bubbles,
    student_names,
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
    SuggestedAction,
)
from app.features.tutor.repository import create_tutor_log

log = logging.getLogger(__name__)


def _student_grade(session, user) -> int:
    """学生年级 = 所属班级年级（ADR-0086 修正）。

    学生不再持有独立年级字段，年级完全由班级承载；未分班学生（无班级）返回 0。
    """
    if user is None or user.class_id is None:
        return 0
    klass = session.get(Class, user.class_id)
    return klass.grade if klass is not None else 0

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


# ── 推荐操作目录（ADR-0072，出题-判断闭环的子代理化见 ADR-0089） ───────────────
#
# 推荐操作是服务端静态目录（零延迟、可控、可单测），不靠 LLM 生成。
# 判断题闭环（出题-判定-讲解）现由 question / tutor 子代理自主驱动（ADR-0089）：
# 出题助手从自由文本/知识点上下文自主判断是否出判断题；伴学答疑从对话历史（题卡含答案）
# 自行判对错、给支架、按需揭示答案。服务端不再有出题/判定的分支逻辑。



# 答案的「跨轮记忆」现由对话历史承载（题卡含答案，前端按需揭示），不再有服务端
# 布尔收口——见 ADR-0089。


# 知识点上下文解析（含 quiz 出题）已下沉到 question 子代理（读取 ctx.extra 的
# knowledge_point_id / courseware 字段自行解析），service 不再持有出题侧的 KP 解析。


def _surface_of(role: Role) -> str:
    """账户角色 → agent_core 调用面（ADR-0088）。

    agent_core 是业务无关内核，其 ``role`` 只有 ``teacher``/``student`` 两种「调用面」，
    零 app.* 依赖，绝不能 import ``Role`` 枚举。故在此把账户角色折算成调用面：
    仅学生走 student 面（注入儿童安全闸门、家长话术），教师与 admin 都走 teacher 面
    （admin 是「超级教师」，复用教师级能力）。
    """
    return "student" if role == Role.STUDENT else "teacher"


def build_suggested_actions(
    *, knowledge_point_id: UUID | None, role: Role, teacher_id: UUID, session: Any
) -> list[SuggestedAction]:
    """ADR-0072：按上下文从固定目录装配推荐操作。

    - 全局目录：问答 / 出几道题练练 / 看错题（角色分叉）/ 查学习进度。
    - 知识点目录（带 id）：举例 / 出一道判断题 / 讲解，并叠加全局能力。
    越权或 id 缺失 → 回落全局目录。
    """
    global_actions: list[SuggestedAction] = [
        SuggestedAction(
            label="我要问个问题", kind="prompt",
            payload="我有学习上的疑问，请帮我解答。",
        ),
        SuggestedAction(
            label="出几道题练练", kind="prompt",
            payload="请给我出几道练习题，巩固一下最近学的知识。",
        ),
    ]
    global_actions.append(
        SuggestedAction(
            label="查看我的错题" if role == Role.STUDENT else "看看孩子错题",
            kind="navigate",
            payload="teacher_task_list",
        )
    )
    global_actions.append(
        SuggestedAction(
            label="查学习进度", kind="prompt",
            payload="请帮我分析一下最近的学习进度和掌握情况。",
        )
    )

    if knowledge_point_id is None:
        return global_actions

    kp = None
    try:
        kp = require_owned(
            session=session, owner_id=teacher_id, model=KnowledgePoint,
            obj_id=knowledge_point_id,
        )
    except AppErrorException:
        kp = None
    if kp is None:
        return global_actions
    name = kp.name

    kp_actions = [
        SuggestedAction(
            label="举几个生活例子", kind="prompt",
            payload=f"请为「{name}」举几个生活中的实际例子，帮助我理解。",
        ),
        SuggestedAction(
            label="出一道判断题", kind="prompt",
            payload=f"请为「{name}」出一道判断题，只展示题目和两个选项，等我回答。",
        ),
        SuggestedAction(
            label="讲解这个知识点", kind="prompt",
            payload=f"请详细讲解「{name}」这个知识点，包括定义、关键性质与常见误区。",
        ),
    ]
    return kp_actions + global_actions


# 判断题的题面引导文案现由出题子代理/前端负责，service 不再单独维护。


# 题卡不再由 service 剥离答案/写 pending_quiz：出题子代理产出的题卡（含答案）原样落库，
# 前端按 `judge` 标记隐藏答案、待揭示；tutor 从历史读答案判定——见 ADR-0089。


# 判断题出题不再有专属子生成器：统一走 question 子代理（文本/上下文路由），由它
# 自主产出 judge 规格——不再经 ``_quiz_generate_stream`` 拦截剥离。见 ADR-0089。


# 无待判定态消费：题目与答案随题卡落库于对话历史，tutor 子代理自行读历史判定，
# 服务端不再维护 pending_quiz 状态机——见 ADR-0089。


# ── 意图信号：现仅承载「文本 + 客户端显式 action 透传」（ADR-0089） ──
#
# 早期版本在此做「信号归一化」：按请求上下文（待判定态 / 出判断题 / 课件提示）服务端硬发射
# 动作键（quiz_judge / quiz_generate / courseware_hint），再交给 `decide` 动作直配。ADR-0089
# 把这些决定权交回子代理：出题由 question 子代理从文本/知识点上下文自主判定是否出判断题；
# 判定由 tutor 子代理从对话历史（题卡含答案）自行判对错；课件提示由 tutor 的 courseware
# 上下文触发。因此这里不再有任何出题/判定分支，只构造纯文本信号（保留客户端显式 action
# 透传，如 task_generate）。


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
    if role == Role.STUDENT:
        student_id = caller.user.id
        teacher_id = caller.user.teacher_id
    else:  # teacher | admin
        teacher_id = caller.user.id
        student_id = None

    # 课件练习与普通助手共用唯一入口；上下文只透传给 SubAgent，不建立 Task / 作答实体。
    courseware = (
        req.courseware.model_dump(mode="json", exclude_none=True)
        if req.courseware is not None
        else None
    )

    # subject 为教育特有概念，由端点计算并透传（agent_core 的 RouteDecision 不感知业务语义）。
    # 课件元数据比按钮文案更可靠：答错后的短句通常不会再次写出学科。
    subject = (
        (req.courseware.subject or "") if req.courseware is not None else ""
    ) or detect_subject(message)

    # 构建运行时依赖（seam 注入）：provider 走单一解析链；retriever 默认 mock；
    # 学生端注入输入安全闸门（首层防御），教师端不拦截。
    engine = (
        resolve_engine(req.model, teacher_id=teacher_id, session=session)
        if teacher_id is not None
        else None
    )
    provider = build_provider(engine=engine)
    # RAG（ADR-0055 §13）：教师端传 (session, teacher_id) 启用资料库向量检索；
    # 学生端 teacher_id 为 None → 自动回落 mock（资料库是教师私有的）。
    retriever = build_retriever(session=session, teacher_id=teacher_id)
    safety = StudentSafety() if role == Role.STUDENT else None
    deps = RuntimeDeps(provider=provider, retriever=retriever, safety=safety)

    # ── 会话定位（先于路由） ──
    # 待判定态定向要在信号归一化阶段知道「这个会话是否在待判定」，故先把既有会话解析
    # 出来（只读归属校验）。**新建**会话仍留在路由之后——它的 ``kind`` 取自路由决策。
    conversation: Conversation | None = None
    conv_id: UUID | None = None

    if req.session_id:
        try:
            existing = get_conversation_by_id(session, UUID(req.session_id))
        except (ValueError, AttributeError):
            existing = None
        if (
            existing is not None
            and existing.teacher_id == teacher_id
            and existing.student_id == student_id
        ):
            conversation = existing
            conv_id = existing.id

    # 预路由：动作键在信号归一化阶段产出（课件练习方向 / 待判定态方向 / 客户端结构化动作），
    # 归属由 SubAgent 清单声明，``decide`` 一次裁决即为最终结果，不再「路由算完再改判业务」。
    # 动作命中但当前角色不可见 → 显式 action_not_visible，见下方转 403。
    signal = IntentSignal(text=message, action=req.action)
    decision = await rt.decide(signal, role=_surface_of(role), deps=deps)
    # 动作不可见（如学生打教师专属动作）：**显式 403**（spec 硬约束），**不要**静默回落成
    # 另一个业务的答非所问，也不要退化成 HTTP 200 + 错误帧。``chat`` 是普通 async 函数
    # （返回迭代器），端点先 ``await`` 它再包 ``StreamingResponse``，故此处抛出会在建流前
    # 被全局异常处理器转成真 403。
    if decision.extra.get("reason") == "action_not_visible":
        raise AppErrorException(
            ErrCode.FORBIDDEN,
            f"当前角色无权执行动作「{decision.extra.get('action')}」。",
        )

    # ── 会话持久化（复用 Conversation/Message，ADR-0026 多轮） ──
    # 续接已有会话并载入历史；否则新建（kind 取路由决策）。
    history: list[dict] | None = None

    if conversation is not None:
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
    else:
        conv_id = uuid4()
        conversation = Conversation(
            id=conv_id,
            kind=decision.business or "agent",  # 路由决策显式给出，不再依赖 THINKING(extra)
            teacher_id=teacher_id,
            student_id=student_id,
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
    # 判断题出题与常规对话共用它——出题段在其上补 ``specs``（由 question 子代理驱动）。
    ctx = SubAgentContext(
        role=role,
        message=message,
        history=history,
        model=req.model,
        skills="",  # runtime 会按 manifest 注入 skill_prompt
        extra={
            "subject": subject,
            "teacher_id": teacher_id,
            "student_id": student_id,
            "grade": (
                req.courseware.grade
                if req.courseware is not None and req.courseware.grade is not None
                else (_student_grade(session, caller.user) if role == Role.STUDENT else 0)
            ),
            "courseware": courseware,
            # ADR-0072：显式下钻知识点 id，便于 SubAgent 精确聚焦（与 courseware 并存）。
            "knowledge_point_id": (
                req.courseware.knowledge_point_id
                if req.courseware is not None
                else None
            ),
            "session_id": str(conv_id),
        },
    )

    # ── 出题 / 判定闭环（ADR-0089，子代理化） ──
    # 判断题的出题与判定不再有服务端分支：question 子代理从文本/知识点上下文自主决定
    # 是否出 judge 规格的题卡（含答案），题卡原样落对话历史、前端按 `judge` 标记隐藏答案
    # 待揭示；tutor 子代理从对话历史读题卡答案自行判对错、给支架、按需揭示。服务端不再
    # 维护 pending_quiz 状态机，也不剥离/注入答案。

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
            role=_surface_of(role),
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

            # ADR-008：学生端伴学交互落 TutorLog（教师可见，F-305）
            if role == Role.STUDENT and decision.business == "tutor":
                try:
                    create_tutor_log(
                        session=session,
                        student_id=student_id,
                        grade=_student_grade(session, caller.user),
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
    student_name: str | None,
    bubble_count: int,
) -> AssistantConversationResp:
    """ORM 行 → 列表行契约（title 的回落规则收口在 ``repository.title_of``）。"""
    return AssistantConversationResp(
        id=conv.id,
        title=title_of(conv, first_user),
        kind=conv.kind,
        student_id=conv.student_id,
        student_name=student_name,
        bubble_count=bubble_count,
        created_at=conv.created_at,
        updated_at=conv.updated_at,
    )


def list_conversations(
    *, session: Any, teacher_id: UUID, limit: int = 50
) -> list[AssistantConversationResp]:
    """教师的历史会话列表（含名下学生的），最近活动倒序。

    「我的 / 学生的」不在这里分段：分段是展示层决策（ADR-0048 选了按娃分两段），
    服务端只保证每行带够判别信息（``student_id`` → 是否可续接，``student_name`` → 归属标签）。
    """
    convs = list_chat_conversations(session=session, teacher_id=teacher_id, limit=limit)
    meta = conversation_meta(session, [c.id for c in convs])
    names = student_names(session, [c.student_id for c in convs if c.student_id])
    out: list[AssistantConversationResp] = []
    for conv in convs:
        m = meta.get(conv.id, {})
        out.append(
            _summary_of(
                conv,
                first_user=m.get("first_user", ""),
                student_name=names.get(conv.student_id) if conv.student_id else None,
                bubble_count=m.get("bubble_count", 0),
            )
        )
    return out


def conversation_detail(
    *, session: Any, conv: Conversation
) -> AssistantConversationDetailResp:
    """一次会话的概要 + 全部气泡。

    只读回放（学生的会话）与恢复续接（教师自己的会话）拿的是**同一份载荷**：
    两者只在「加载后能不能继续发消息」上有区别，那是前端的模式状态，不是两种数据。
    """
    bubbles = [
        AssistantBubbleResp(**b) for b in read_conversation_bubbles(session, conv.id)
    ]
    first_user = next((b.text for b in bubbles if b.role == "user"), "")
    names = student_names(session, [conv.student_id] if conv.student_id else [])
    return AssistantConversationDetailResp(
        conversation=_summary_of(
            conv,
            first_user=first_user,
            student_name=names.get(conv.student_id) if conv.student_id else None,
            bubble_count=len(bubbles),
        ),
        bubbles=bubbles,
    )


def delete_conversations(
    *, session: Any, teacher_id: UUID, ids: list[UUID]
) -> int:
    """批量删除本教师名下的会话及其消息（多选删除，ADR-0048 补充）。

    归属校验与消息级联删除都收口在 repository（与读路径同一份可见轮次判定相反，
    这里只做「按 id + teacher_id 删干净」）。返回实际删掉的会话条数。
    """
    return repo_delete_conversations(
        session=session, teacher_id=teacher_id, ids=ids
    )
