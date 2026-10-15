"""悬浮助手统一端点（ADR-0024 / 0025 / 0026）：所有 AI 功能经此单入口。

``POST /api/v1/assistant/chat`` 接收自由文本 + 角色身份，经 agent_core.AgentRuntime 路由到
对应 SubAgent，以 SSE 流式推送 AG-UI 事件帧（USER_MESSAGE / THINKING / TOOL_CALL /
TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE）。

- 双端通用：教师与学生共用此端点（Caller 依赖解析角色）。
- 学生端角色感知 + 输入安全（ADR-008）；教师端可出题/查任务/伴学。
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

from app.core.deps import CallerDep, SessionDep
from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned_conversation
from app.db.models import Role
from app.features.assistant import service as assistant_service
from app.features.assistant.schemas import (
    AssistantChatReq,
    AssistantConversationDetailResp,
    AssistantConversationResp,
    AssistantConversationsDeleteReq,
    SuggestedAction,
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


@router.get("/suggested-actions", response_model=list[SuggestedAction])
def suggested_actions(
    *, session: SessionDep, caller: CallerDep,
    knowledge_point_id: UUID | None = Query(default=None),
) -> list[SuggestedAction]:
    """空态推荐操作目录（ADR-0072，只读静态目录）：无 id→全局，有 id→知识点目录(叠加全局)。

    教师/学生通用（``CallerDep`` 解析角色）；知识点归属经 ``require_owned`` 校验，
    越权或查不到回落全局目录。导航类动作的 payload 是既有 ``ShellDestination`` 枚举。
    """
    # admin 复用 teacher 面（ADR-0088）：教师与 admin 都以自身为 owner；仅学生走 teacher_id。
    teacher_id = (
        caller.user.id
        if caller.role in (Role.TEACHER, Role.ADMIN)
        else caller.user.teacher_id
    )
    return assistant_service.build_actions(
        situation="empty", knowledge_point_id=knowledge_point_id, role=caller.role,
        teacher_id=teacher_id, session=session,
    )


@router.get("/conversations", response_model=list[AssistantConversationResp])
def list_conversations(
    *,
    session: SessionDep,
    caller: CallerDep,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[AssistantConversationResp]:
    """**我的**历史会话列表，最近活动倒序（ADR-0048，归属口径 ADR-0096）。

    教师与学生走同一条路径（``CallerDep``）：每人只看**自己**的会话——教师不再看到
    名下学生的（ADR-0048 §3 的反转，见 ADR-0096），学生则第一次有了自己的列表。
    列表里每一条都可续接，因此响应不含「只读」判别字段。
    """
    return assistant_service.list_conversations(
        session=session, user=caller.user, limit=limit
    )


@router.get("/conversations/{conv_id}", response_model=AssistantConversationDetailResp)
def get_conversation(
    *, session: SessionDep, caller: CallerDep, conv_id: UUID
) -> AssistantConversationDetailResp:
    """一次会话的概要 + 全部气泡（恢复续接）。不属于本人 → 403。

    归属走 ``core.guard`` 的会话判据：教师只开自己聊的（学生的会话他看不到），
    学生只开自己聊的。不存在与不属于抛同一个错（403），不把越权降级成 404。
    """
    conv = require_owned_conversation(
        session=session,
        user=caller.user,
        conv_id=conv_id,
        code=ErrCode.FORBIDDEN,
        message="Not your conversation",
    )
    return assistant_service.conversation_detail(session=session, conv=conv)


@router.delete("/conversations", response_model=int)
def delete_conversations(
    *, session: SessionDep, caller: CallerDep, body: AssistantConversationsDeleteReq
) -> int:
    """批量删除**本人**名下的会话及其关联消息（多选删除，ADR-0048 补充）。

    双端通用（``CallerDep``），与列表 / 详情同一判据。``ids`` 只认本人拥有的会话；
    越权的 id（他人会话 / 不存在）被归属过滤掉，静默忽略，不会误删他人数据。

    会话与消息是两张表、无 FK 级联（ADR-0048 有意不做的缺口），删除在 repository
    内按「先消息后会话」的顺序完成。返回实际删除的会话条数。
    """
    return assistant_service.delete_conversations(
        session=session, user=caller.user, ids=body.ids
    )
