"""AI 运行可观测：调试落库助手（ADR-0022 / 终态化于 ADR-0023）。

提供 start_agent_run / log_agent_message / finish_agent_run，供出题/批改等 Agent 运行
记录多步过程（系统提示 → 检索 → 推理 → 题卡/答案 → 工具调用）。

单流约束（ADR-0023）：生成 / 流式期间**零 DB 写**。所有消息先缓冲在内存，
仅当一次运行**完整结束**时由 finish_agent_run 一次性把 conversation + 全部 message 落库。
这样「agent 输出 → DB」不再有生成期并行写入的分叉，调试库只是运行结束后的观察侧终态 sink。

所有写操作均 try/except 包裹：落库失败绝不阻断主流程（同 flows._log_tutor）。
conversation.parent_id 为 NOT NULL（owner 隔离），故 parent_id 缺失时 start 返回 None，
后续 log/finish 自动变 no-op，安全降级。
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from uuid import UUID

from sqlmodel import Session

from app.core.db import engine as db_engine
from app.features.ai.repository import (
    add_message,
    create_conversation,
)


@dataclass
class _Message:
    role: str
    step: str = "output"
    content: str = ""
    payload: dict | None = None
    model: str | None = None
    input_safe: bool = True
    output_safe: bool = True
    blocked: bool = False
    block_reason: str | None = None
    latency_ms: int | None = None
    usage: dict | None = None


@dataclass
class _RunBuffer:
    kind: str
    parent_id: UUID
    child_id: UUID | None = None
    model: str | None = None
    title: str | None = None
    ref_task_id: UUID | None = None
    status: str = "running"
    messages: list[_Message] = field(default_factory=list)


# 内存缓冲区：conv_id -> 本次运行的消息累积。finish 时清空并落库。
_buffers: dict[UUID, _RunBuffer] = {}


def start_agent_run(
    *,
    kind: str,
    parent_id: UUID | None,
    child_id: UUID | None = None,
    model: str | None = None,
    title: str | None = None,
    ref_task_id: UUID | None = None,
) -> UUID | None:
    """开启一次 Agent 运行：仅分配内存缓冲区并返回 conv_id，不触库。

    parent_id 缺失（匿名/越权降级）时返回 None，后续 log/finish 自动 no-op。
    """
    if parent_id is None:
        return None
    conv_id = uuid.uuid4()
    _buffers[conv_id] = _RunBuffer(
        kind=kind,
        parent_id=parent_id,
        child_id=child_id,
        model=model,
        title=title,
        ref_task_id=ref_task_id,
    )
    return conv_id


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
    """累积一条消息到内存缓冲区（无 DB 写）。运行完整结束前绝不落库。"""
    buf = _buffers.get(conversation_id) if conversation_id is not None else None
    if buf is None:
        return
    buf.messages.append(
        _Message(
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
    )


def finish_agent_run(*, conversation_id: UUID | None, status: str = "done") -> None:
    """一次运行完整结束：把 conversation + 全部 message **一次性**落库（终态 sink）。

    缓冲期间任何异常都吞掉，绝不阻断主流程。运行从未结束（崩溃）则整段丢弃——调试
    信息丢失可接受，主业务数据不受影响。
    """
    if conversation_id is None:
        return
    buf = _buffers.pop(conversation_id, None)
    if buf is None:
        return
    try:
        with Session(db_engine) as s:
            conv = create_conversation(
                session=s,
                kind=buf.kind,
                parent_id=buf.parent_id,
                child_id=buf.child_id,
                model=buf.model,
                title=buf.title,
                ref_task_id=buf.ref_task_id,
                status=status,
            )
            for i, m in enumerate(buf.messages):
                add_message(
                    session=s,
                    conversation_id=conv.id,
                    turn=i + 1,
                    role=m.role,
                    step=m.step,
                    content=m.content,
                    payload=m.payload,
                    model=m.model,
                    input_safe=m.input_safe,
                    output_safe=m.output_safe,
                    blocked=m.blocked,
                    block_reason=m.block_reason,
                    latency_ms=m.latency_ms,
                    usage=m.usage,
                )
            s.commit()
    except Exception:
        pass
