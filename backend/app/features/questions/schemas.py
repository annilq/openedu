"""Pydantic schemas for the questions (bank) feature."""

from datetime import datetime
from typing import Any
from uuid import UUID

from sqlmodel import Field, SQLModel


class BankQuestionItem(SQLModel):
    """题库列表项（教师私有视图，即可见 answer）。"""

    id: UUID
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
    # 已归档时间；None = 在用（ADR-0053 P2）。前端据此给「已归档」徽标。
    archived_at: datetime | None = None
    # 学期（ADR-0061 §J）：'' = 整学年/不限。详情要展示——它同时决定讲解匹配
    # 哪份知识点模板（同学期优先、整学年兜底）。此前本 schema 漏了它，详情里
    # 「学期」永远显示成整学年。
    semester: str = ""
    # 交互讲解实例（ADR-0061 §U）：快照优先、缺失则实时解析、再无则图库兜底。
    # 此前本 schema 漏了它，题库详情**永远**没有图形（前端拿到 null 就不渲染）。
    scene_spec: dict[str, Any] | None = None


class BankListResp(SQLModel):
    """题库列表响应（ADR-0053）：游标分页信封。

    ``total`` 只用于「还有 N 条」提示，不参与翻页判定——它是取页那一刻的快照，
    期间插入新题后必然失真。翻页只看 ``next_cursor``。
    """

    items: list[BankQuestionItem]
    total: int
    page: int
    page_size: int
    # 下一页游标；None = 已到底。客户端原样回传，不得解析。
    next_cursor: str | None = None


class TaskFromBankCreate(SQLModel):
    """选项 A：从题库新建任务。"""

    title: str = Field(max_length=255)
    student_id: UUID | None = None
    question_ids: list[UUID]


class BankQuestionsAdd(SQLModel):
    """选项 B：加入已有草稿任务。"""

    question_ids: list[UUID]


class DeleteQuestionsReq(SQLModel):
    """批量删除题库题：传待删 Question.id 列表。"""

    ids: list[UUID]


class DeleteQuestionsResult(SQLModel):
    """批量硬删结果：全量级联删除，分组返回。

    - ``deleted``：成功删除的题库题 id；
    - ``deleted_tasks``：因失去全部题目而被连带删除的任务 id；
    - ``skipped_forbidden``：不存在 / 非本教师所有、未删除的 id。
    """

    deleted: list[UUID] = []
    deleted_tasks: list[UUID] = []  # 因变空而被连带删除的任务
    skipped_forbidden: list[UUID] = []  # 不存在 / 非本教师所有，跳过


class ArchiveQuestionsReq(SQLModel):
    """批量归档 / 恢复题库题（ADR-0053 P2）。

    ``archived=True`` 归档、``False`` 恢复。恢复是归档存在的理由——被任务引用的题
    删不掉，教师只能堆着；可恢复才敢点。
    """

    ids: list[UUID]
    archived: bool = True


class ArchiveQuestionsResult(SQLModel):
    """批量归档 / 恢复结果。"""

    updated: list[UUID] = []
    skipped_forbidden: list[UUID] = []  # 不存在 / 非本教师所有，跳过


class QuestionUsageItem(SQLModel):
    """题库题被某任务引用的反查结果项。"""

    task_id: UUID
    title: str
    status: str  # draft | ready | assigned | done
    created_at: datetime | None = None


class QuestionUsagesResp(SQLModel):
    """题库题被哪些任务引用（owner 隔离）。闭环「用过 N 次 → 在哪里用」。"""

    items: list[QuestionUsageItem] = []
