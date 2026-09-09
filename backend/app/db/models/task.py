import uuid
from datetime import datetime

from sqlalchemy import JSON, DateTime
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc


class TaskBase(SQLModel):
    title: str = Field(max_length=255)
    status: str = Field(max_length=16, default="draft")  # draft|ready|assigned|done
    # 兴趣题模式：本卷聚焦的兴趣主题（WF-4），整卷共享、用于审阅打标与整卷重生成复现。
    focus_interest: list[str] | None = Field(default=None, sa_type=JSON)


class Task(TaskBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")
    child_id: uuid.UUID | None = Field(default=None, foreign_key="user.id")  # 可空，assigned 时绑
    # 出题所用模型引用（内置 id / ModelConfig id）；缺省 None = 后端回退（mock/langchain）。
    # 落库以便「整卷重生成 / 单题重生成」沿用同一模型，避免静默回退 mock。
    model: str | None = Field(default=None)
    # 原始生成规格：from-generated 完整保存，整卷重生成时按此规格重跑并覆盖草稿项（R-Q2=c）。
    specs: list[dict] | None = Field(default=None, sa_type=JSON)
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class TaskQuestion(SQLModel, table=True):
    """派发快照层（ADR-0004 D3）。

    创建时即深拷贝 Question 全字段为独立副本；draft 态可编辑（除 qtype），
    ready/assigned 后冻结。question_id 指向源 Question（可空，重生成场景无源），
    用于作答提交与错题归集的桥梁（AnswerRecord/WrongQuestion 仍指向 Question.id）。
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    task_id: uuid.UUID = Field(foreign_key="task.id", index=True)
    question_id: uuid.UUID | None = Field(default=None, foreign_key="question.id")
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = Field(default=None, sa_type=JSON)
    answer: str | None = None
    explanation: str | None = None
    difficulty: str | None = None
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
