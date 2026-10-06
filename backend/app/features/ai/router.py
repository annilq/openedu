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

from app.core.deps import CurrentTeacher, SessionDep
from app.core.errors import ErrCode
from app.core.guard import require_owned
from app.db.models import Conversation
from app.features.ai.repository import get_conversation_messages, list_conversations
from app.features.ai.schemas import (
    ConversationDetailResp,
    ConversationResp,
    MessageResp,
)

router = APIRouter(prefix="/ai", tags=["ai"])


@router.get("/debug/conversations", response_model=list[ConversationResp])
def debug_list_conversations(
    *, session: SessionDep, teacher: CurrentTeacher, kind: str | None = None, limit: int = 100
) -> list[ConversationResp]:
    """教师查看自家 AI 运行列表（出题/批改/agent），可按 kind 过滤，时间倒序。"""
    rows = list_conversations(session=session, teacher_id=teacher.id, kind=kind, limit=limit)
    return [ConversationResp(**r.model_dump()) for r in rows]


@router.get("/debug/conversations/{conv_id}", response_model=ConversationDetailResp)
def debug_get_conversation(
    *, session: SessionDep, teacher: CurrentTeacher, conv_id: UUID
) -> ConversationDetailResp:
    """教师查看一次 AI 运行的概要 + 全部步骤（按 turn 回放）。越权（非本教师）→ 403。"""
    conv = require_owned(
        session=session,
        owner_id=teacher.id,
        model=Conversation,
        obj_id=conv_id,
        code=ErrCode.FORBIDDEN,
        message="Not your conversation",
    )
    msgs = get_conversation_messages(session=session, conversation_id=conv_id)
    return ConversationDetailResp(
        conversation=ConversationResp(**conv.model_dump()),
        messages=[MessageResp(**m.model_dump()) for m in msgs],
    )
