import uuid
from enum import Enum

from sqlalchemy import Column, String
from sqlmodel import Field, SQLModel


class Role(str, Enum):
    """账户角色（ADR-0088）：学生 / 教师 / 管理员。

    - 取值与既有库字符串一致（``student``/``teacher``），新增 ``admin``。
    - ``admin`` 是「超级教师」：拥有教师级能力 + 越教师边界的运维/审计只读
      （看全部 AI 运行轨迹、跨教师排障）。儿童合规红线见 ADR-0088：admin 默认
      只看元数据/脱敏内容，全文走破窗留痕。
    - 注意与 agent_core 的「调用面（surface）」区分：调用面只有 ``teacher``/
      ``student`` 两种（业务无关，agent_core 零 app.* 依赖），admin 复用 teacher 面。
    """

    STUDENT = "student"
    TEACHER = "teacher"
    ADMIN = "admin"


class UserBase(SQLModel):
    username: str = Field(unique=True, index=True, max_length=64)
    display_name: str = Field(max_length=64)
    # 角色枚举：DB 仍存 VARCHAR(16)（与历史库字符串兼容，无迁移），Python 侧为 Role。
    # sa_column 显式用 String 而非原生 Enum 类型，避免 SQLite/Postgres 改列类型与
    # 原生 enum 类型创建的迁移负担；值由 Pydantic 在读写时与 Role 互转。
    role: Role = Field(
        default=Role.STUDENT,
        sa_column=Column(String(16), nullable=False, default=Role.STUDENT.value),
    )
    is_active: bool = True


class User(UserBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    hashed_password: str
    # 教师 1—* 学生 自关联
    teacher_id: uuid.UUID | None = Field(default=None, foreign_key="user.id")
    # 学生归属班级（可空：未分班 / 删班后降级）。班级实体见 app.db.models.class_entity。
    class_id: uuid.UUID | None = Field(default=None, foreign_key="classes.id")
