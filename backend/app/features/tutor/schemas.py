"""Pydantic schemas for the tutor (AI companion log) feature.

娃娃端实时答疑的请求/响应体（``TutorAskReq`` / ``TutorAnswer``）已随旧 ``POST /tutor/ask``
一起废弃（ADR-0024 收敛到 ``POST /assistant/chat``），此处只留家长侧日志响应。
"""

from uuid import UUID

from sqlmodel import SQLModel


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
