"""Pydantic schemas for the tutor (AI companion log) feature."""

from uuid import UUID

from sqlmodel import Field, SQLModel


class TutorAskReq(SQLModel):
    subject: str = Field(max_length=32)
    grade: int
    knowledge_point: str = Field(default="", max_length=128)
    context: str | None = None
    question: str = Field(min_length=1, max_length=2000)
    # 可选模型引用：内置 id / ModelConfig id；缺省走家长默认或全局 DEFAULT_MODEL
    model: str | None = None


class TutorAnswer(SQLModel):
    answer: str
    blocked: bool = False
    reason: str | None = None


class TutorLogResp(SQLModel):
    """单条 AI 答疑日志（家长端查看，F-305）。"""

    id: UUID
    grade: int
    subject: str
    knowledge_point: str
    question: str
    answer: str
    input_safe: bool
    output_safe: bool
    blocked: bool
    created_at: object  # datetime | None
