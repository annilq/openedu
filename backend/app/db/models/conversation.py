import uuid
from datetime import datetime

from sqlalchemy import JSON, DateTime
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc


class Conversation(SQLModel, table=True):
    """一次 AI Agent 运行的容器（ADR-0022）。

    - kind：运行类型（开放 str），question|grade|agent|...
    - parent_id：owner 隔离（呼应题库闭环）；child_id：触发者（出题可为 null=家长）
    - model：所用模型引用（内置 id / ModelConfig id）
    - ref_task_id：关联生成的 Task，便于追溯出题结果
    - status：running|done|error|blocked
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    kind: str = Field(max_length=32, index=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id", index=True)
    child_id: uuid.UUID | None = Field(default=None, foreign_key="user.id")
    model: str | None = Field(default=None, max_length=255)
    title: str | None = Field(default=None, max_length=255)
    ref_task_id: uuid.UUID | None = Field(default=None, foreign_key="task.id")
    status: str = Field(default="running", max_length=16)
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    updated_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class Message(SQLModel, table=True):
    """Conversation 内带 role+step 的一步（ADR-0022）。

    - role：system|user|assistant|tool（谁产生）
    - step：input|retrieval|reasoning|generation|tool_call|output|error（运行到哪一步）
    - content：人类可读文本；payload：结构化原始数据（题卡 dict/模型原始响应/检索块/工具参数）
    - input_safe/output_safe/blocked：安全标记（ADR-008，调试也能定位被拦步骤）
    - latency_ms / usage：可观测（耗时 / token：{prompt_tokens, completion_tokens}）
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    conversation_id: uuid.UUID = Field(foreign_key="conversation.id", index=True)
    turn: int = Field(default=0)
    role: str = Field(max_length=16)
    step: str = Field(default="output", max_length=16)
    content: str = Field(default="")
    payload: dict | None = Field(default=None, sa_type=JSON)
    model: str | None = Field(default=None, max_length=255)
    input_safe: bool = True
    output_safe: bool = True
    blocked: bool = False
    block_reason: str | None = Field(default=None, max_length=255)
    latency_ms: int | None = Field(default=None)
    usage: dict | None = Field(default=None, sa_type=JSON)
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
