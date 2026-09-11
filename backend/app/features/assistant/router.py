"""悬浮助手统一端点（ADR-0024 / 0025 / 0026）：所有 AI 功能经此单入口。

``POST /api/v1/assistant/chat`` 接收自由文本 + 角色身份，经 agent_core.AgentRuntime 路由到
对应 SubAgent，以 SSE 流式推送 AG-UI 事件帧（USER_MESSAGE / THINKING / TOOL_CALL /
TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE）。

- 双端通用：家长与孩子共用此端点（Caller 依赖解析角色）。
- 娃娃端角色感知 + 输入安全 + 使用配额（ADR-008 / T10）；家长端可出题/查任务/伴学。
- 会话持久化复用 ``Conversation`` / ``Message``（ADR-0022 升级为助手会话，supersede）。
- 统一编排由 agent_core 提供（ADR-0031）：``AgentRuntime`` + ``RuntimeDeps``（provider /
  retriever / safety 注入）+ ``SubAgentContext``（业务字段走 ``extra``）。本端点只负责
  鉴权 / 配额 / 落库，不感知任何路由或 subagent 内部细节。

废弃的旧 AI 端点（统一收敛到此）：``/ai/tutor/ask``、``/ai/tasks/generate``、``/tutor/ask``。
"""
from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

from app.core.deps import CallerDep, SessionDep
from app.core.errors import AppErrorException, ErrCode
from app.features.assistant import service as assistant_service
from app.features.assistant.schemas import AssistantChatReq

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
