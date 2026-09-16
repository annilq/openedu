"""悬浮助手统一端点（ADR-0024 / 0025 / 0026）：所有 AI 功能经此单入口。

``POST /api/v1/assistant/chat`` 接收自由文本 + 角色身份，经 agent_core.AgentRuntime 路由到
对应 SubAgent，以 SSE 流式推送 AG-UI 事件帧（USER_MESSAGE / THINKING / TOOL_CALL /
TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE）。

- 双端通用：家长与孩子共用此端点（Caller 依赖解析角色）。
- 娃娃端角色感知 + 输入安全（ADR-008）；家长端可出题/查任务/伴学。
- 会话持久化复用 ``Conversation`` / ``Message``（ADR-0022 升级为助手会话，supersede）。
- 统一编排由 agent_core 提供（ADR-0031）：``AgentRuntime`` + ``RuntimeDeps``（provider /
  retriever / safety 注入）+ ``SubAgentContext``（业务字段走 ``extra``）。本端点只负责
  鉴权 / 落库，不感知任何路由或 subagent 内部细节。

废弃的旧 AI 端点（统一收敛到此）：``/ai/tutor/ask``、``/ai/tasks/generate``、``/tutor/ask``。

会话历史的**用户面**读端点（ADR-0048）也在此：``GET /assistant/conversations`` 与
``GET /assistant/conversations/{id}``。它与 ``/ai/debug/conversations`` 是**两个消费者**
而非两条实现：这边返回对话气泡，那边返回运行轨迹。
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Query
from fastapi.responses import StreamingResponse

from app.core.deps import CallerDep, CurrentParent, SessionDep
from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned
from app.db.models import Conversation
from app.features.assistant import service as assistant_service
from app.features.assistant.schemas import (
    AssistantChatReq,
    AssistantConversationDetailResp,
    AssistantConversationResp,
    AssistantConversationsDeleteReq,
)

router = APIRouter(prefix="/assistant", tags=["assistant"])


@router.post("/chat")
async def assistant_chat(req: AssistantChatReq, caller: CallerDep, session: SessionDep) -> StreamingResponse:
    """悬浮助手对话：SSE 流式返回 AG-UI 事件。

    本端点只做 HTTP 适配：空消息校验 + 包 ``StreamingResponse``。全部编排
    （预路由 / 配额 / 会话 upsert / 事件流折叠持久化）在 ``assistant_service.chat``。
    """
    message = (req.message or "").strip()
    if not message:
        raise AppErrorException(ErrCode.CHAT_EMPTY_MESSAGE, "消息不能为空")

    return StreamingResponse(
        await assistant_service.chat(caller=caller, req=req, session=session),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.get("/conversations", response_model=list[AssistantConversationResp])
def list_conversations(
    *,
    session: SessionDep,
    parent: CurrentParent,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[AssistantConversationResp]:
    """家长的历史会话列表（含名下娃娃的），最近活动倒序（ADR-0048）。

    **家长专属**（``CurrentParent``）：娃娃端的会话列表被有意留空——孩子看到自己
    「被拦过」的记录是负面强化，而「找回我问过的那道题」对孩子是次要需求。
    这是不对称，不是遗漏。故本轮也没有 child-scoped 的等价路由。
    """
    return assistant_service.list_conversations(
        session=session, parent_id=parent.id, limit=limit
    )


@router.get("/conversations/{conv_id}", response_model=AssistantConversationDetailResp)
def get_conversation(
    *, session: SessionDep, parent: CurrentParent, conv_id: UUID
) -> AssistantConversationDetailResp:
    """一次会话的概要 + 全部气泡（回放 / 恢复续接）。越权（非本家长）→ 403。

    归属走 ``core.guard`` 单一实现；娃娃的会话也归家长所有（``parent_id`` 是家长），
    所以孩子那条会话其家长能读到——这正是「家长可查看孩子在问什么」的实现方式，
    读到的内容与孩子当时看到的一致（工具出参在落库前就按角色剥过答案，ADR-0033）。
    """
    conv = require_owned(
        session=session,
        owner_id=parent.id,
        model=Conversation,
        obj_id=conv_id,
        code=ErrCode.FORBIDDEN,
        message="Not your conversation",
    )
    return assistant_service.conversation_detail(session=session, conv=conv)


@router.delete("/conversations", response_model=int)
def delete_conversations(
    *, session: SessionDep, parent: CurrentParent, body: AssistantConversationsDeleteReq
) -> int:
    """批量删除本家长名下的会话及其关联消息（多选删除，ADR-0048 补充）。

    **家长专属**（``CurrentParent``，与列表 / 回放同一口径）。``ids`` 只认
    ``parent_id`` 匹配的会话——孩子的会话也归家长所有，一并可删；越权的 id
    （其他家长 / 不存在）被归属过滤掉，静默忽略，不会误删他人数据。

    会话与消息是两张表、无 FK 级联（ADR-0048 有意不做的缺口），删除在 repository
    内按「先消息后会话」的顺序完成。返回实际删除的会话条数。
    """
    return assistant_service.delete_conversations(
        session=session, parent_id=parent.id, ids=body.ids
    )
