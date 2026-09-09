"""Pydantic request/response schemas for the auth feature."""

from uuid import UUID

from sqlalchemy import JSON
from sqlmodel import Field, SQLModel

from app.db.models import UserBase


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
    id: UUID


class UsersPublic(SQLModel):
    data: list[UserPublic]
    count: int


class Token(SQLModel):
    access_token: str
    token_type: str = "bearer"


class TokenPayload(SQLModel):
    sub: str | None = None


# 通用响应体（原 `Message` 名已让给 conversation/message 调试库的 Message 表，见 ADR-0022）。
class StatusMessage(SQLModel):
    message: str
