"""AI 运行可观测：调试落库助手（ADR-0022）。

提供 start_agent_run / log_agent_message / finish_agent_run，供出题/批改等 Agent 运行
记录多步过程（系统提示 → 检索 → 推理 → 题卡/答案 → 工具调用）。

所有写操作均 try/except 包裹：调试日志失败绝不阻断主流程（同 flows._log_tutor）。
conversation.parent_id 为 NOT NULL（owner 隔离），故 parent_id 缺失时 start 返回 None，
后续 log/finish 自动变 no-op，安全降级。
"""
from uuid import UUID

from sqlmodel import Session

from app.core.db import engine as db_engine
from app.crud import add_message, create_conversation, finish_conversation


def start_agent_run(
    *,
    kind: str,
    parent_id: UUID | None,
    child_id: UUID | None = None,
    model: str | None = None,
    title: str | None = None,
    ref_task_id: UUID | None = None,
) -> UUID | None:
    if parent_id is None:
        return None
    try:
        with Session(db_engine) as s:
            conv = create_conversation(
                session=s,
                kind=kind,
                parent_id=parent_id,
                child_id=child_id,
                model=model,
                title=title,
                ref_task_id=ref_task_id,
                status="running",
            )
            return conv.id
    except Exception:
        return None


def log_agent_message(
    *,
    conversation_id: UUID | None,
    role: str,
    step: str = "output",
    content: str = "",
    payload: dict | None = None,
    model: str | None = None,
    input_safe: bool = True,
    output_safe: bool = True,
    blocked: bool = False,
    block_reason: str | None = None,
    latency_ms: int | None = None,
    usage: dict | None = None,
) -> None:
    if conversation_id is None:
        return
    try:
        with Session(db_engine) as s:
            add_message(
                session=s,
                conversation_id=conversation_id,
                role=role,
                step=step,
                content=content,
                payload=payload,
                model=model,
                input_safe=input_safe,
                output_safe=output_safe,
                blocked=blocked,
                block_reason=block_reason,
                latency_ms=latency_ms,
                usage=usage,
            )
    except Exception:
        pass


def finish_agent_run(*, conversation_id: UUID | None, status: str = "done") -> None:
    if conversation_id is None:
        return
    try:
        with Session(db_engine) as s:
            finish_conversation(session=s, conversation_id=conversation_id, status=status)
    except Exception:
        pass
