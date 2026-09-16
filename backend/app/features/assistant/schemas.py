"""悬浮助手契约（ADR-0024 / 0025 / 0026）。

请求体从 ``router`` 收口到此处：router 只负责 HTTP 适配，不应持有业务契约。

ADR-0048 起本模块也持有**会话历史的读契约**（列表 / 回放）。它与
``app/features/ai/schemas.py`` 的 ``ConversationResp`` / ``MessageResp`` 刻意不复用：
那两份是**运行轨迹**的调试投影（全部 step、原始 payload、安全标记），
这两份是**对话**的用户面投影（气泡 + 卡片）。两者的消费者与保真度要求都不同，
合并会逼用户面拖走工具原始载荷，也会逼审计侧丢掉保真度。
"""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

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


class AssistantConversationResp(SQLModel):
    """会话列表行：一段可续接的多轮对话（ADR-0048）。

    - ``title``：会话名（首条用户消息截断；历史会话无 title 时由服务端回落）。
    - ``kind``：**首轮**路由结果的展示标签，不承担分组或筛选——续接轮不更新它，
      拿它当类型筛选会撒谎。
    - ``child_id`` / ``child_name``：``None`` 表示这是家长自己的会话；非空即孩子的，
      前端据此分「只读回放」与「可续接」两条路径。
    - ``bubble_count``：可见轮次数（用户的提问数 + 回答数），列表行上的「几轮」。
    """

    id: UUID
    title: str
    kind: str
    child_id: UUID | None = None
    child_name: str | None = None
    bubble_count: int = 0
    created_at: datetime | None = None
    updated_at: datetime | None = None


class AssistantBubbleResp(SQLModel):
    """回放的一条消息气泡。

    ``cards`` 是落库的 DATA **整帧**列表（``{type, result}``），原样透传给前端按种类
    分派渲染器——服务端不在这里拼展示串（ADR-0042）。

    **没有 ``blocked``**：``Message`` 上那组安全标记列从未被写入，被拦记录只存在于
    ``TutorLog``（即 F-305 的「已拦截」徽标）。回放因此渲染不出「已拦截」，
    这是有意的不对称，别用「顺带补一个字段」把它掩盖成看起来能用的空值。
    """

    role: str
    text: str = ""
    cards: list[dict] = []


class AssistantConversationDetailResp(SQLModel):
    """一次会话的回放：概要 + 全部气泡（供只读查看或恢复续接）。"""

    conversation: AssistantConversationResp
    bubbles: list[AssistantBubbleResp] = []
