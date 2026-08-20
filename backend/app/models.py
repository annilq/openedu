import uuid
from datetime import UTC, date, datetime

from sqlalchemy import JSON, DateTime, UniqueConstraint
from sqlmodel import Field, SQLModel


def get_datetime_utc() -> datetime:
    return datetime.now(UTC)


# ───────────────────────── 用户 / 账号 ─────────────────────────
class UserBase(SQLModel):
    username: str = Field(unique=True, index=True, max_length=64)
    display_name: str = Field(max_length=64)
    role: str = Field(max_length=16, default="child")  # parent | child
    grade: int | None = Field(default=None)
    is_active: bool = True


class UserCreate(UserBase):
    password: str = Field(min_length=4, max_length=128)


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


# ───────────────────────── 任务 / 题目 ─────────────────────────
class TaskBase(SQLModel):
    title: str = Field(max_length=255)
    subject: str = Field(max_length=32)
    grade: int
    knowledge_point: str = Field(max_length=128)
    qtype: str = Field(max_length=16)  # choice|fill|calc|open
    difficulty: str = Field(max_length=16, default="medium")
    count: int = Field(default=1)
    status: str = Field(max_length=16, default="pending")


class TaskCreate(TaskBase):
    child_id: uuid.UUID


class Task(TaskBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")
    child_id: uuid.UUID = Field(foreign_key="user.id")
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class Question(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    task_id: uuid.UUID = Field(foreign_key="task.id")
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = Field(default=None, sa_type=JSON)
    answer: str | None = None
    explanation: str | None = None
    difficulty: str | None = None


class AnswerRecord(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    question_id: uuid.UUID = Field(foreign_key="question.id")
    child_id: uuid.UUID = Field(foreign_key="user.id")
    student_answer: str
    correct: bool = False
    score: float = 0.0


class Checkin(SQLModel, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id")
    task_id: uuid.UUID = Field(foreign_key="task.id")
    checkin_date: date = Field(default_factory=date.today)


class WrongQuestion(SQLModel, table=True):
    """错题集：按 child + question 唯一，重复答错只累加次数，不建多条（故事 13）。"""

    __table_args__ = (UniqueConstraint("child_id", "question_id"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    child_id: uuid.UUID = Field(foreign_key="user.id", index=True)
    question_id: uuid.UUID = Field(foreign_key="question.id")
    first_wrong_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    wrong_count: int = Field(default=1)


# ───────────────────────── API 响应模型 ─────────────────────────
class QuestionResp(SQLModel):
    id: uuid.UUID
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
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    difficulty: str
    count: int
    status: str
    questions: list[QuestionResp] = []


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


# ───────────────────────── 通用 ─────────────────────────
class Token(SQLModel):
    access_token: str
    token_type: str = "bearer"


class TokenPayload(SQLModel):
    sub: str | None = None


class Message(SQLModel):
    message: str
