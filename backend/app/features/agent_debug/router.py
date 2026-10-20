"""AI 运行可观测端点（ADR-0022 / 0026）。

仅保留教师只读回放接口：查看自家 Agent 运行（出题/答疑/查询）的概要与各步。
这些不是「AI 生成」接口，而是教师可见的调试轨迹（ADR-008），故不并入
``/api/v1/assistant/chat`` 的生成流，但读的是同一张 ``Conversation``/``Message`` 表
（助手会话统一落库，supersede ADR-0022 的 debug_log）。

所有 AI 生成能力已统一收敛到 ``POST /api/v1/assistant/chat``；
原 ``/ai/tutor/ask``、``/ai/tasks/generate``（Genkit flow 端点）已废弃。
"""
from uuid import UUID

from fastapi import APIRouter

from app.core.deps import CurrentAdmin, CurrentTeacher, SessionDep
from app.core.errors import ErrCode
from app.core.guard import require_owned_or_admin
from app.db.models import Conversation, Role
from app.features.agent_debug.masking import full_message, mask_message
from app.features.agent_debug.repository import (
    create_break_glass,
    get_conversation_messages,
    list_break_glass,
    list_conversations,
)
from app.features.agent_debug.schemas import (
    BreakGlassLogResp,
    BreakGlassReason,
    ConversationDetailResp,
    ConversationResp,
)

router = APIRouter(prefix="/ai", tags=["ai"])


@router.get("/debug/conversations", response_model=list[ConversationResp])
def debug_list_conversations(
    *, session: SessionDep, teacher: CurrentTeacher, kind: str | None = None, limit: int = 100
) -> list[ConversationResp]:
    """教师查看自家 AI 运行列表（出题/批改/agent），可按 kind 过滤，时间倒序。

    admin（ADR-0088）越教师边界：``teacher_id=None`` 表示看全部 AI 运行。
    """
    # admin 看全部；教师只看自家（teacher_id=自身）。
    teacher_id = None if teacher.role == Role.ADMIN else teacher.id
    rows = list_conversations(session=session, teacher_id=teacher_id, kind=kind, limit=limit)
    return [ConversationResp(**r.model_dump()) for r in rows]


@router.get("/debug/conversations/{conv_id}", response_model=ConversationDetailResp)
def debug_get_conversation(
    *, session: SessionDep, teacher: CurrentTeacher, conv_id: UUID
) -> ConversationDetailResp:
    """教师查看一次 AI 运行的概要 + 全部步骤（按 turn 回放）。越权（非本教师）→ 403。

    admin（ADR-0088）豁免归属：可查看任意教师的 AI 运行（只读审计/排障）。
    """
    conv = require_owned_or_admin(
        session=session,
        owner_id=teacher.id,
        model=Conversation,
        obj_id=conv_id,
        user=teacher,
        code=ErrCode.FORBIDDEN,
        message="Not your conversation",
    )
    msgs = get_conversation_messages(session=session, conversation_id=conv_id)
    # 默认脱敏（ADR-0088 ticket 03）：管理员看不到全文，只有破窗显原文；
    # 教师作为 owner 看自家运行全文（合规红线只针对 admin 站着读所有孩子）。
    messages = [mask_message(m) for m in msgs] if teacher.role == Role.ADMIN else [
        full_message(m) for m in msgs
    ]
    return ConversationDetailResp(
        conversation=ConversationResp(**conv.model_dump()),
        messages=messages,
    )


@router.post(
    "/debug/conversations/{conv_id}/reveal",
    response_model=ConversationDetailResp,
)
def break_glass_reveal(
    *,
    session: SessionDep,
    admin: CurrentAdmin,
    conv_id: UUID,
    body: BreakGlassReason,
) -> ConversationDetailResp:
    """破窗：管理员显式查看某次运行全文（含脱敏的 tool 参数/结果），留痕审计。

    仅 admin 可调用；非 admin（教师/学生）调此 → 403（``require_admin`` 拦截）。
    留痕记录谁/何时/读了哪段对话/理由；原文始终留在业务 DB，不外流到独立观测后端。
    """
    conv = require_owned_or_admin(
        session=session,
        owner_id=admin.id,
        model=Conversation,
        obj_id=conv_id,
        user=admin,
        code=ErrCode.NOT_FOUND,
        message="对话不存在",
    )
    msgs = get_conversation_messages(session=session, conversation_id=conv_id)
    # 先定稿响应：create_break_glass 内的 commit 会把本会话的 ORM 实例 expire，
    # 须在写审计前把 SQLModel 响应对象构建好（它们是脱离 ORM 的纯对象）。
    conversation_resp = ConversationResp(**conv.model_dump())
    messages = [full_message(m) for m in msgs]
    create_break_glass(
        session=session,
        actor_id=admin.id,
        conversation_id=conv_id,
        reason=body.reason,
    )
    return ConversationDetailResp(conversation=conversation_resp, messages=messages)


@router.get("/debug/break-glass-logs", response_model=list[BreakGlassLogResp])
def list_break_glass_logs(
    *,
    session: SessionDep,
    admin: CurrentAdmin,
    conversation_id: UUID | None = None,
) -> list[BreakGlassLogResp]:
    """破窗访问留痕列表（admin 可查，ADR-0088 ticket 03）。"""
    rows = list_break_glass(session=session, conversation_id=conversation_id)
    return [BreakGlassLogResp(**r.model_dump()) for r in rows]
