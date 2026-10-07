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


class CoursewareContext(SQLModel):
    """课堂课件练习上下文（ADR-0067 §3.6）。

    与 ``focus_interest`` 同样只经 ``SubAgentContext.extra`` 透传，不对应任务、
    作答或掌握度实体；字段可空以兼容孤儿课件与尚未补齐的旧草稿。
    """

    courseware_id: UUID | None = None
    section_id: str | None = None
    knowledge_point: str | None = None
    # ADR-0072：知识点精确 id（无同名漂移）。优先于 `knowledge_point` name 口径；
    # 缺失时回落 name（保持对 SectionPractice 的兼容）。
    knowledge_point_id: UUID | None = None
    subject: str | None = None
    grade: int | None = None
    semester: str | None = None


class SuggestedAction(SQLModel):
    """助手空态下方的「推荐操作」（ADR-0072）。

    由服务端按上下文从固定目录装配（**非 LLM 生成**），零延迟、可控、可单测。
    与 ADR-0042 的 `actions`（纯导航枚举）是两套概念：本类是会话空态的*建议入口*。

    - ``kind='prompt'``：``payload`` 是预置提示文本，前端点击即 ``send(payload)``。
    - ``kind='navigate'``：``payload`` 是既有 ``ShellDestination`` 枚举（如
      ``teacher_question_bank``），前端点击走壳导航。
    - ``quiz``：True 时该 prompt 动作触发出题-判断-引导闭环（后端出判断题 + 写
      pending_quiz），前端以 ``send(payload, quiz: true)`` 下发。仅 prompt 类使用。
    """

    label: str
    kind: str  # 'prompt' | 'navigate'
    payload: str
    quiz: bool = False


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
    # ADR-0072：出题-判断-引导闭环的触发标记。为真时后端绕开常规 LLM 路由，
    # 直接复用 question 管线出一道判断题并写入 pending_quiz，等待用户自然语言 yes/no 判定。
    quiz: bool = Field(default=False)
    # ADR-0067：课件练习只把课堂语境透传给 SubAgent，不创建任务或作答记录。
    courseware: CoursewareContext | None = None


class AssistantConversationResp(SQLModel):
    """会话列表行：一段可续接的多轮对话（ADR-0048）。

    - ``title``：会话名（首条用户消息截断；历史会话无 title 时由服务端回落）。
    - ``kind``：**首轮**路由结果的展示标签，不承担分组或筛选——续接轮不更新它，
      拿它当类型筛选会撒谎。
    - ``student_id`` / ``student_name``：``None`` 表示这是教师自己的会话；非空即学生的，
      前端据此分「只读回放」与「可续接」两条路径。
    - ``bubble_count``：可见轮次数（用户的提问数 + 回答数），列表行上的「几轮」。
    """

    id: UUID
    title: str
    kind: str
    student_id: UUID | None = None
    student_name: str | None = None
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


class AssistantConversationsDeleteReq(SQLModel):
    """批量删除会话（多选删除，ADR-0048 补充）。

    ``ids`` 只认**本教师名下**的会话：学生的会话也归教师所有（``teacher_id`` 是教师），
    所以一并可删；越权的 id（其他教师 / 不存在）被后端按归属过滤掉，静默忽略，
    不会误删他人数据。
    """

    ids: list[UUID]
