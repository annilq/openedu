import uuid
from datetime import datetime

from sqlalchemy import DateTime, UniqueConstraint
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc


class TaskAssignment(SQLModel, table=True):
    """作业派发对象关系（ADR-0069）：任务与学生的多对多派发展开。

    - 一道任务可派发给一个班级（展开为 N 个学生）或显式学生列表，去重后每行一个学生。
    - 唯一约束 ``(task_id, student_id)`` 必须写在 ``CREATE TABLE`` 里——
      SQLite 的 ``ALTER TABLE ADD CONSTRAINT`` 被静默忽略（ADR-0061 §R），
      写在模型里由 ``create_all`` 生成新库、迁移里手建旧库，二者必须同名同约束。
    - ``completed_at`` 为空 = 该学生未完成；全部派发对象都填了 ``completed_at`` →
      任务整体转 ``done``（语义在 :mod:`app.features.tasks.service` 维护）。
    - 旧单列 ``task.student_id`` 保留作过渡（只读），本表是派发唯一事实源。
    """

    __tablename__ = "taskassignment"  # 与 core/db.py 迁移 CREATE TABLE 同名

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    task_id: uuid.UUID = Field(foreign_key="task.id", index=True)
    student_id: uuid.UUID = Field(foreign_key="user.id", index=True)
    assigned_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    completed_at: datetime | None = Field(
        default=None,
        sa_type=DateTime(timezone=True),  # type: ignore
    )

    __table_args__ = (UniqueConstraint("task_id", "student_id"),)
