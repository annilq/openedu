import uuid

from sqlmodel import Field, SQLModel


class UserBase(SQLModel):
    username: str = Field(unique=True, index=True, max_length=64)
    display_name: str = Field(max_length=64)
    role: str = Field(max_length=16, default="student")  # teacher | student
    grade: int | None = Field(default=None)
    is_active: bool = True


class User(UserBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    hashed_password: str
    # 教师 1—* 学生 自关联
    teacher_id: uuid.UUID | None = Field(default=None, foreign_key="user.id")
    # 学生归属班级（可空：未分班 / 删班后降级）。班级实体见 app.db.models.class_entity。
    class_id: uuid.UUID | None = Field(default=None, foreign_key="classes.id")
