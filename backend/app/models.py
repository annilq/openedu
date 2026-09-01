import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import JSON, DateTime, UniqueConstraint
from sqlmodel import Field, SQLModel


def get_datetime_utc() -> datetime:
    return datetime.now(UTC)


def get_review_due_utc() -> datetime:
    """错题首次归集时：1 天后到期复习（遗忘曲线首档间隔）。"""
    return datetime.now(UTC) + timedelta(days=1)


def get_usage_date_utc() -> date:
    """当日用量行的日期口径：统一 UTC（与 created_at 存储时区一致）。"""
    return datetime.now(UTC).date()


# ───────────────────────── 用户 / 账号 ─────────────────────────
class UserBase(SQLModel):
    username: str = Field(unique=True, index=True, max_length=64)
    display_name: str = Field(max_length=64)
    role: str = Field(max_length=16, default="child")  # parent | child
    grade: int | None = Field(default=None)
    is_active: bool = True
    # 兴趣画像（WF-1 定稿）：受控分类叶子 key 列表 + 自由文本。
    # 取值形态 {categories: list[str], free_text: str|null}；空/未设 = None。
    interests: dict | None = Field(default=None, sa_type=JSON)


class UserCreate(UserBase):
    password: str = Field(min_length=4, max_length=128)


class UserUpdate(SQLModel):
    """家长编辑娃娃资料（WF-5）：仅昵称/年级/兴趣可改，账号密码锁定不编辑。

    所有字段可选；仅传非空字段进行局部更新。
    """

    display_name: str | None = Field(default=None, max_length=64)
    grade: int | None = Field(default=None)
    interests: dict | None = Field(default=None, sa_type=JSON)


class LoginRequest(SQLModel):
    username: str
    password: str


class UserPublic(UserBase):
    id: uuid.UUID


class UsersPublic(SQLModel):
    data: list[UserPublic]
    count: int


class User(UserBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    hashed_password: str
    # 家长 1—* 娃娃 自关联
    parent_id: uuid.UUID | None = Field(default=None, foreign_key="user.id")


# ───────────────────────── 任务 / 题目 / 题库快照（ADR-0004） ─────────────────────────
class TaskBase(SQLModel):
    title: str = Field(max_length=255)
    status: str = Field(max_length=16, default="draft")  # draft|ready|assigned|done
    # 兴趣题模式：本卷聚焦的兴趣主题（WF-4），整卷共享、用于审阅打标与整卷重生成复现。
    focus_interest: list[str] | None = Field(default=None, sa_type=JSON)


class TaskCreate(SQLModel):
    """单科兼容入口（内部转调 batch-generate）。"""
    title: str = Field(max_length=255)
    child_id: uuid.UUID | None = None  # 可空，支持"先成卷晚点派"


class TaskSpec(SQLModel):
    """多学科一卷批量生成的一条规格（ADR-0004 D4）。"""
    subject: str = Field(max_length=32)
    grade: int
    knowledge_point: str = Field(max_length=128)
    qtype: str = Field(max_length=16)  # choice|fill|calc|open
    difficulty: str = Field(max_length=16, default="medium")
    count: int = Field(default=1, ge=1)


class TaskBatchCreate(SQLModel):
    """POST /tasks/batch-generate 请求体。"""
    title: str = Field(max_length=255)
    child_id: uuid.UUID | None = None  # 可空，支持"先成卷晚点派"
    specs: list[TaskSpec]
    # 兴趣题模式（WF-4）：显式聚焦的兴趣主题列表；留空/缺省 = 后端自动轻融入娃娃画像。
    focus_interest: list[str] | None = None
    # 可选模型引用：内置 id / ModelConfig id；缺省走家长默认或全局 DEFAULT_MODEL
    model: str | None = None


class TaskFromGenerated(SQLModel):
    """POST /tasks/from-generated 请求体。

    流式出题（/ai/tasks/generate）逐题返回的题卡已在前端渲染；本端点把这些
    「已生成且经安全闸门」的题卡一次性落库为 draft 任务，避免二次生成与超时。
    `questions` 形态与 QuestionOut 对齐（snake_case：knowledge_point 等）。
    """

    title: str = Field(max_length=255)
    child_id: uuid.UUID | None = None  # 可空，支持"先成卷晚点派"
    specs: list[TaskSpec]  # 原始规格，持久化到 Task.specs 以便整卷重生成
    # 兴趣题模式（WF-4）：显式聚焦的兴趣主题列表；与生成时保持一致。
    focus_interest: list[str] | None = None
    # 可选模型引用：内置 id / ModelConfig id；落库以便重生成沿用。
    model: str | None = None
    # 已流式生成、待落库的题卡（QuestionPreview.toJson 形态）。
    questions: list[dict]


class Task(TaskBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")
    child_id: uuid.UUID | None = Field(default=None, foreign_key="user.id")  # 可空，assigned 时绑
    # 出题所用模型引用（内置 id / ModelConfig id）；缺省 None = 后端回退（mock/langchain）。
    # 落库以便「整卷重生成 / 单题重生成」沿用同一模型，避免静默回退 mock。
    model: str | None = Field(default=None)
    # 原始生成规格：batch-generate 完整保存，整卷重生成时按此规格重跑并覆盖草稿项（R-Q2=c）。
    specs: list[dict] | None = Field(default=None, sa_type=JSON)
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class Question(SQLModel, table=True):
    """题库层（ADR-0004 D2）：Question 表本身即题库，删 task_id 独立实体，可跨 Task 复用。

    parent_id（题库复用闭环）：归属家长，实现 owner 隔离，避免多家庭互通题库。
    旧库通过 db.run_migrations 回填（见 backend/app/core/db.py）。
    """
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")  # 题库 owner 隔离（闭环）
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


class ModelConfig(SQLModel, table=True):
    """家长自定义模型（ADR-0015 / 票据 08）：仅家长可增删改，api_key 经 Fernet 加密。

    provider ∈ {ollama, openai_compat}；base_url 仅 openai_compat 自定义端点需要，
    ollama 缺省走 settings.OLLAMA_BASE_URL。is_default 标记家长默认模型。
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")
    label: str = Field(max_length=64)
    provider: str = Field(max_length=32)
    base_url: str | None = Field(default=None, max_length=512)
    model_name: str = Field(max_length=128)
    api_key_enc: str | None = Field(default=None, max_length=1024)
    is_default: bool = Field(default=False)


class AnswerRecord(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    question_id: uuid.UUID = Field(foreign_key="question.id")
    child_id: uuid.UUID = Field(foreign_key="user.id")
    student_answer: str
    correct: bool = False
    score: float = 0.0
    source: str = Field(max_length=16, default="practice")  # practice|review
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class Checkin(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id")
    task_id: uuid.UUID = Field(foreign_key="task.id")
    checkin_date: date = Field(default_factory=date.today)


class WrongQuestion(SQLModel, table=True):
    """错题集：按 child + question 唯一，重复答错只累加次数，不建多条（故事 13）。

    遗忘曲线调度字段（故事 14/17）：
    - review_stage：当前阶段 0..4，对应间隔 1/2/4/7/15 天
    - last_wrong_at：最近一次答错时间，作为计时器起点（重复答错重置）
    - due_at：下次复习到期时间
    """

    __table_args__ = (UniqueConstraint("child_id", "question_id"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id", index=True)
    question_id: uuid.UUID = Field(foreign_key="question.id")
    first_wrong_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    wrong_count: int = Field(default=1)
    review_stage: int = Field(default=0)
    last_wrong_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    due_at: datetime | None = Field(
        default_factory=get_review_due_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


# ───────────────────────── API 响应模型 ─────────────────────────
class QuestionResp(SQLModel):
    id: uuid.UUID  # TaskQuestion.id（娃娃端读快照）
    question_id: uuid.UUID | None = None  # 源 Question.id，作答提交与错题归集用
    subject: str = ""
    grade: int = 0
    stem: str
    options: list[str] | None = None
    qtype: str
    knowledge_point: str
    explanation: str = ""
    # 娃娃端接口恒为 None，防作弊
    answer: str | None = None


class TaskResp(SQLModel):
    id: uuid.UUID
    title: str
    status: str
    # 原始生成规格（整卷重生成可用；前端展示方便）
    specs: list[dict] | None = None
    questions: list[QuestionResp] = []


# ───────── 题库复用闭环（GET /questions / POST /tasks/from-bank 等） ─────────
class BankQuestionItem(SQLModel):
    """题库列表项（家长私有视图，即可见 answer）。"""
    id: uuid.UUID
    subject: str = ""
    grade: int = 0
    stem: str
    options: list[str] | None = None
    qtype: str
    knowledge_point: str
    difficulty: str | None = None
    answer: str | None = None
    explanation: str | None = None
    created_at: datetime | None = None
    usage_count: int = 0  # 被多少个 Task 引用（复用度）


class BankListResp(SQLModel):
    items: list[BankQuestionItem]
    total: int
    page: int
    page_size: int


class TaskFromBankCreate(SQLModel):
    """选项 A：从题库新建任务。"""
    title: str = Field(max_length=255)
    child_id: uuid.UUID | None = None
    question_ids: list[uuid.UUID]


class BankQuestionsAdd(SQLModel):
    """选项 B：加入已有草稿任务。"""
    question_ids: list[uuid.UUID]


class TaskQuestionEdit(SQLModel):
    """PUT /tasks/{task_id}/questions/{tq_id} 编辑请求体（仅 draft 态）。

    可改：题干/选项/答案/解析/知识点（ADR-0004 D6）。
    禁改：qtype（防娃娃端 UI 渲染崩），不在本 schema 暴露。
    """
    stem: str | None = None
    options: list[str] | None = None
    answer: str | None = None
    explanation: str | None = None
    knowledge_point: str | None = None


class AnswerSubmit(SQLModel):
    question_id: uuid.UUID
    student_answer: str


class AnswerResult(SQLModel):
    correct: bool
    score: float
    explanation: str = ""


class CheckinResult(SQLModel):
    ok: bool
    checkin_date: date


class ProgressResp(SQLModel):
    child_id: uuid.UUID
    total: int
    correct: int
    accuracy: float
    streak_days: int
    checkin_days: int


class WrongQuestionResp(SQLModel):
    """错题列表项：含题干与答案/解析，供复习使用。"""

    id: uuid.UUID
    question_id: uuid.UUID
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = None
    answer: str | None = None
    explanation: str = ""
    wrong_count: int
    first_wrong_at: datetime | None = None
    review_stage: int = 0
    due_at: datetime | None = None


class ReviewAnswerSubmit(SQLModel):
    wrong_question_id: uuid.UUID
    student_answer: str


class ReviewItemResp(SQLModel):
    """到期复习项（娃娃端）：含题干、不含答案，附调度进度。"""

    wrong_question_id: uuid.UUID
    question_id: uuid.UUID
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = None
    explanation: str = ""
    wrong_count: int
    review_stage: int
    next_interval_days: int
    due_at: datetime | None = None


class KnowledgeMasteryResp(SQLModel):
    """单个知识点的掌握度（家长看板，F-204）。"""

    knowledge_point: str
    subject: str
    grade: int
    total_answers: int
    correct_answers: int
    accuracy: float
    active_wrong: int
    max_review_stage: int
    score: float
    level: str


class MasteryResp(SQLModel):
    """知识点掌握度看板（家长端）。"""

    child_id: uuid.UUID
    total_knowledge_points: int
    mastered_count: int
    items: list[KnowledgeMasteryResp] = []


# ───────────────────────── AI 伴学答疑（三期 F-302~305） ─────────────────────────
class TutorLog(SQLModel, table=True):
    """AI 伴学答疑交互日志（F-305，家长可查）。"""

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id", index=True)
    grade: int
    subject: str = Field(max_length=32)
    knowledge_point: str = Field(default="", max_length=128)
    question: str
    answer: str
    input_safe: bool = True
    output_safe: bool = True
    blocked: bool = False  # 因安全原因返回兜底（未调用/未采用模型输出）
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


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

    id: uuid.UUID
    grade: int
    subject: str
    knowledge_point: str
    question: str
    answer: str
    input_safe: bool
    output_safe: bool
    blocked: bool
    created_at: datetime | None = None


# ───────── AI 使用管控（T10，故事 23/26） ─────────
class TutorQuota(SQLModel, table=True):
    """家长按娃配置的 AI 使用管控（每娃一条）。

    - daily_ask_limit：每日提问条数上限；None → 回退全局 TUTOR_DAILY_LIMIT；0 → 今日禁用
    - daily_minutes_limit：每日累计使用分钟上限；None → 不限时；0 → 今日禁用
    - allowed_subjects：允许提问的学科白名单；None → 不限
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id", unique=True, index=True)
    daily_ask_limit: int | None = None
    daily_minutes_limit: int | None = None
    allowed_subjects: list[str] | None = Field(default=None, sa_type=JSON)
    updated_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class TutorUsage(SQLModel, table=True):
    """当日 AI 使用累计（按 child + 日期唯一）。

    次数口径沿用 TutorLog 计数（count_tutor_today）；
    此表只累计服务端实测的答疑耗时秒数，用于时长上限判定。
    """

    __table_args__ = (UniqueConstraint("child_id", "usage_date"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id", index=True)
    usage_date: date = Field(default_factory=get_usage_date_utc)
    used_seconds: int = Field(default=0)


class TutorQuotaUpdate(SQLModel):
    """家长设置管控的请求体；字段缺省（None）= 清除该项限制（恢复默认）。"""

    daily_ask_limit: int | None = None
    daily_minutes_limit: int | None = None
    allowed_subjects: list[str] | None = None


class TutorQuotaResp(SQLModel):
    child_id: uuid.UUID
    daily_ask_limit: int | None = None
    daily_minutes_limit: int | None = None
    allowed_subjects: list[str] | None = None


class TutorUsageResp(SQLModel):
    """当日用量（家长端展示）；同时回带生效的限额，便于前端直接展示剩余。"""

    child_id: uuid.UUID
    date: date
    asks_today: int
    used_seconds: int
    ask_limit: int | None = None
    minutes_limit: int | None = None
    allowed_subjects: list[str] | None = None


# ───────────────────────── 通用 ─────────────────────────
class Token(SQLModel):
    access_token: str
    token_type: str = "bearer"


class TokenPayload(SQLModel):
    sub: str | None = None


class Message(SQLModel):
    message: str
