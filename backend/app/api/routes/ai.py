"""AI 统一端点（ADR-0015 / 迁移 08b）：薄路由层。

设计要点（守 ADR-003 隔离 / ADR-008 安全）：
- 鉴权：CurrentChild（答疑）/ CurrentParent（出题）。
- 使用管控（答疑次数/时长/学科范围）+ 输入安全：在委托 flow 之前完成。
- 用户上下文（child_id / parent_id / role）以 context 注入 flow；flow 内部据此
  取兴趣池、落库日志，无需再解析 token（ADR-003 隔离：genkit 仅出现在 app/ai）。
- 通过 `genkit_fastapi.handle_genkit_request` 以**原生 action 端点**暴露 flow，
  返回原生 SSE / {"result": ...} 线格式；前端用 package:genkit client.dart 的
  `defineRemoteAction` 直连（见迁移文档 08b 与 技术架构_Flutter）。
- 本端点为统一后唯一 AI 入口；tutor.py 的 /tutor/ask（LangChainProvider 老路径）
  与 stream.py 在并行过渡期保留，迁移 Phase 3 退役。
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, status
from genkit_fastapi import handle_genkit_request
from starlette.responses import Response

from app.ai.flows import tasks_generate, tutor_ask
from app.api.deps import CurrentChild, CurrentParent, SessionDep
from app.core.config import settings
from app.crud import (
    count_tutor_today,
    get_conversation_messages,
    get_tutor_quota,
    get_tutor_usage_today,
    list_conversations,
)
from app.domain import REASON_SUBJECT_SCOPE, check_quota
from app.domain.safety import check_input
from app.models import (
    Conversation,
    ConversationDetailResp,
    ConversationResp,
    MessageResp,
    User,
)

router = APIRouter(prefix="/ai", tags=["ai"])


def _tutor_limits(session, child_id: UUID) -> tuple[int | None, int | None, list[str] | None]:
    """解析生效限额：未配置/None 的提问上限回退全局 TUTOR_DAILY_LIMIT（与 tutor.py 一致）。"""
    quota = get_tutor_quota(session=session, child_id=child_id)
    ask_limit: int | None = settings.TUTOR_DAILY_LIMIT
    minutes_limit: int | None = None
    allowed_subjects: list[str] | None = None
    if quota is not None:
        if quota.daily_ask_limit is not None:
            ask_limit = quota.daily_ask_limit
        minutes_limit = quota.daily_minutes_limit
        allowed_subjects = quota.allowed_subjects
    return ask_limit, minutes_limit, allowed_subjects


@router.post("/tutor/ask", response_model=None)
async def tutor_ask_endpoint(
    request: Request, child: CurrentChild, session: SessionDep
) -> Response | dict[str, object]:
    """娃娃答疑：原生 Genkit flow 端点（SSE 流式 / 一次性 result）。

    先校验 使用管控 + 输入安全，再委托 tutor_ask flow（flow 内做输出安全 + 日志落库）。
    前端：defineRemoteAction('/api/v1/ai/tutor/ask', ...).stream({subject,grade,knowledge_point,question,...})
    """
    body = await request.json()
    data = body.get("data", body) if isinstance(body, dict) else {}
    subject = str(data.get("subject", "")).strip()
    question = str(data.get("question", ""))
    knowledge_point = str(data.get("knowledge_point", ""))
    free_text = str(data.get("context") or "")

    # 输入安全：越狱 / 非学习类主题 → 拒绝（ADR-008）
    if not check_input(f"{question} {knowledge_point} {free_text}").safe:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="输入含不适当内容")

    # 使用管控：学科范围 → 次数 → 时长
    ask_limit, minutes_limit, allowed_subjects = _tutor_limits(session, child.id)
    usage = get_tutor_usage_today(session=session, child_id=child.id)
    used_seconds = usage.used_seconds if usage is not None else 0
    used = count_tutor_today(session=session, child_id=child.id)
    decision = check_quota(
        subject=subject,
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
        raise HTTPException(status_code=code, detail=decision.message)

    context = {"child_id": str(child.id), "parent_id": str(child.parent_id), "role": "child"}
    return await handle_genkit_request(request, action=tutor_ask, context=context)


@router.post("/tasks/generate", response_model=None)
async def tasks_generate_endpoint(
    request: Request, parent: CurrentParent, session: SessionDep
) -> Response | dict[str, object]:
    """家长出题：原生 Genkit flow 端点（题卡逐张浮现 SSE / 一次性 result）。

    校验 child 归属（防越权出题）+ 输入安全，再委托 tasks_generate flow。
    前端：defineRemoteAction('/api/v1/ai/tasks/generate', ...).stream({child_id?,specs,focus_interest?,model?})
    """
    body = await request.json()
    data = body.get("data", body) if isinstance(body, dict) else {}
    child_id = data.get("child_id")

    # 归属校验：显式指定 child_id 时必须是本家长名下娃娃（防越权出题）
    if child_id:
        try:
            cid = UUID(str(child_id))
        except (ValueError, TypeError, AttributeError):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your child")
        child = session.get(User, cid)
        if child is None or child.parent_id != parent.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your child")

    # 输入安全：对各题知识点/主题做整体越狱检测
    specs = data.get("specs") or []
    blob = " ".join(
        f"{s.get('subject', '')} {s.get('knowledge_point', '')}"
        for s in specs
        if isinstance(s, dict)
    )
    if blob and not check_input(blob).safe:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="输入含不适当内容")

    context = {"parent_id": str(parent.id), "role": "parent"}
    return await handle_genkit_request(request, action=tasks_generate, context=context)


# ───────── AI 运行可观测：只读调试接口（ADR-0022） ─────────
# 仅供家长（owner）回放自家 Agent 运行，用于调试 Agent 输出与定位 bad case。
# 与 TutorLog（答疑合规）分离；本接口只读，不写入。
@router.get("/debug/conversations", response_model=list[ConversationResp])
def debug_list_conversations(
    *, session: SessionDep, parent: CurrentParent, kind: str | None = None, limit: int = 100
) -> list[ConversationResp]:
    """家长查看自家 AI 运行列表（出题/批改/agent），可按 kind 过滤，时间倒序。"""
    rows = list_conversations(session=session, parent_id=parent.id, kind=kind, limit=limit)
    return [ConversationResp(**r.model_dump()) for r in rows]


@router.get("/debug/conversations/{conv_id}", response_model=ConversationDetailResp)
def debug_get_conversation(
    *, session: SessionDep, parent: CurrentParent, conv_id: UUID
) -> ConversationDetailResp:
    """家长查看一次 AI 运行的概要 + 全部步骤（按 turn 回放）。越权（非本家长）→ 403。"""
    conv = session.get(Conversation, conv_id)
    if conv is None or conv.parent_id != parent.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your conversation")
    msgs = get_conversation_messages(session=session, conversation_id=conv_id)
    return ConversationDetailResp(
        conversation=ConversationResp(**conv.model_dump()),
        messages=[MessageResp(**m.model_dump()) for m in msgs],
    )
