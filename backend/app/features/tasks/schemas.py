"""Pydantic schemas for the tasks feature."""

import uuid
from datetime import date, datetime

from sqlmodel import Field, SQLModel


class TaskSpec(SQLModel):
    """多学科一卷批量生成的一条规格（ADR-0004 D4）。"""

    subject: str = Field(max_length=32)
    grade: int
    knowledge_point: str = Field(max_length=128)
    qtype: str = Field(max_length=16)  # choice|fill|calc|open
    difficulty: str = Field(max_length=16, default="medium")
    count: int = Field(default=1, ge=1)


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


class TaskResp(SQLModel):
    id: uuid.UUID
    title: str
    status: str
    # 原始生成规格（整卷重生成可用；前端展示方便）
    specs: list[dict] | None = None
    questions: list["QuestionResp"] = []  # noqa: F821
    # 派发对象（列表/详情展示“对应娃娃”用）
    child_id: uuid.UUID | None = None
    # 创建时间（列表排序/展示用）
    created_at: datetime | None = None


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


class TaskFromBankCreate(SQLModel):
    """选项 A：从题库新建任务。"""

    title: str = Field(max_length=255)
    child_id: uuid.UUID | None = None
    question_ids: list[uuid.UUID]


class BankQuestionsAdd(SQLModel):
    """选项 B：加入已有草稿任务。"""

    question_ids: list[uuid.UUID]


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
