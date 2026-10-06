import uuid

from sqlalchemy import JSON
from sqlmodel import Field, SQLModel


class UserBase(SQLModel):
    username: str = Field(unique=True, index=True, max_length=64)
    display_name: str = Field(max_length=64)
    role: str = Field(max_length=16, default="student")  # teacher | student
    grade: int | None = Field(default=None)
    is_active: bool = True
    # 兴趣画像（WF-1 定稿）：受控分类叶子 key 列表 + 自由文本。
    # 取值形态 {categories: list[str], free_text: str|null}；空/未设 = None。
    interests: dict | None = Field(default=None, sa_type=JSON(none_as_null=True))


class User(UserBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    hashed_password: str
    # 教师 1—* 学生 自关联
    teacher_id: uuid.UUID | None = Field(default=None, foreign_key="user.id")
