"""悬浮助手契约（ADR-0024 / 0025 / 0026）。

请求体从 ``router`` 收口到此处：router 只负责 HTTP 适配，不应持有业务契约。
"""
from __future__ import annotations

from sqlmodel import Field, SQLModel


class AssistantChatReq(SQLModel):
    """悬浮助手对话请求体。

    WF-4 兴趣题模式：``focus_interest`` 为显式聚焦主题（如「恐龙」「太空」），
    经 ctx.extra 透传给出题 SubAgent，注入出题 prompt 让情境围绕该主题展开。
    """

    message: str = Field(min_length=1, max_length=2000)
    session_id: str | None = None
    model: str | None = None
    history: list[dict] | None = None
    focus_interest: list[str] | None = None
