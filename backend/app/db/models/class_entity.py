"""班级实体（ADR-0068：教师端规模化第一块地基）。

班级归属当前教师（``teacher_id``），自带年级（1–9）。学生（``User``，``role='student'``）
通过 ``User.class_id`` 关联到班级；删除班级时只把学生的 ``class_id`` 置空，学生账号与
错题数据保留（见 ``app.features.classes.service``）。

``(teacher_id, name)`` 唯一性**不依赖 DB 约束**：SQLite ``ALTER TABLE`` 静默忽略
``UNIQUE``（ADR-0061 §R），且老库重建代价大；故由 service 层显式查重拒绝（见 ticket 01）。
"""

import uuid
from datetime import datetime

from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc


class Class(SQLModel, table=True):
    __tablename__ = "classes"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    teacher_id: uuid.UUID = Field(index=True, foreign_key="user.id")
    name: str = Field(max_length=64)
    grade: int = Field()  # 1–9
    created_at: datetime = Field(default_factory=get_datetime_utc)
