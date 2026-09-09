"""Shared cross-cutting dependencies (feature-first architecture, ADR-0027).

Moved from `app/api/deps.py`. Holds auth/session resolution used by every feature
router. ORM `User` comes from the centralized `app.db.models`; `TokenPayload` is an
auth feature schema.
"""

import uuid
from collections.abc import Generator
from dataclasses import dataclass
from typing import Annotated

import jwt
from fastapi import Depends
from fastapi.security import OAuth2PasswordBearer
from jwt.exceptions import InvalidTokenError
from pydantic import ValidationError
from sqlmodel import Session

from app.core import security
from app.core.config import settings
from app.core.db import engine
from app.core.errors import AppErrorException, ErrCode
from app.db.models import User
from app.features.auth.schemas import TokenPayload

reusable_oauth2 = OAuth2PasswordBearer(
    tokenUrl=f"{settings.API_V1_STR}/auth/login", auto_error=False
)


def get_db() -> Generator[Session]:
    with Session(engine) as session:
        yield session


SessionDep = Annotated[Session, Depends(get_db)]
TokenDep = Annotated[str, Depends(reusable_oauth2)]


def get_current_user(session: SessionDep, token: TokenDep) -> User:
    if not token:
        raise AppErrorException(
            ErrCode.UNAUTHORIZED, "未登录或登录已过期"
        )
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[security.ALGORITHM]
        )
        token_data = TokenPayload(**payload)
    except (InvalidTokenError, ValidationError):
        raise AppErrorException(
            ErrCode.AUTH_INVALID_TOKEN, "凭证校验失败，请重新登录"
        )
    if token_data.sub is None:
        raise AppErrorException(
            ErrCode.AUTH_INVALID_TOKEN, "Token 缺少 sub 字段"
        )
    user = session.get(User, uuid.UUID(token_data.sub))
    if not user:
        raise AppErrorException(ErrCode.NOT_FOUND, "用户不存在")
    if not user.is_active:
        raise AppErrorException(
            ErrCode.AUTH_INACTIVE_USER, "账号已停用，请联系家长"
        )
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def require_parent(current_user: CurrentUser) -> User:
    if current_user.role != "parent":
        raise AppErrorException(
            ErrCode.AUTH_PARENT_ONLY, "该接口仅家长账号可用"
        )
    return current_user


CurrentParent = Annotated[User, Depends(require_parent)]


def require_child(current_user: CurrentUser) -> User:
    if current_user.role != "child":
        raise AppErrorException(
            ErrCode.AUTH_CHILD_ONLY, "该接口仅娃娃账号可用"
        )
    return current_user


CurrentChild = Annotated[User, Depends(require_child)]


@dataclass
class Caller:
    """统一调用者（悬浮助手双端通用）：role + 用户实体。

    家长端 parent_id=用户自身；娃娃端 child_id=用户自身、parent_id=其家长（配额/owner 用）。
    """

    role: str
    user: User


def get_caller(current_user: CurrentUser) -> Caller:
    return Caller(role=current_user.role, user=current_user)


CallerDep = Annotated[Caller, Depends(get_caller)]
