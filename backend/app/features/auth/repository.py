"""Repository layer for the auth feature (user CRUD + password verification)."""

import uuid

from sqlmodel import Session

from app.core.security import get_password_hash, verify_password
from app.db.models import User
from app.features.auth.schemas import UserCreate


def create_user(
    *,
    session: Session,
    user_create: UserCreate,
    role: str,
    parent_id: uuid.UUID | None = None,
) -> User:
    db_obj = User.model_validate(
        user_create,
        update={
            "hashed_password": get_password_hash(user_create.password),
            "role": role,
            "parent_id": parent_id,
        },
    )
    session.add(db_obj)
    session.commit()
    session.refresh(db_obj)
    return db_obj


def get_user_by_username(*, session: Session, username: str) -> User | None:
    from sqlmodel import select

    return session.exec(select(User).where(User.username == username)).first()


def get_user(*, session: Session, user_id: uuid.UUID) -> User | None:
    return session.get(User, user_id)


# 用户不存在时仍做一次假哈希校验，防止时序攻击
DUMMY_HASH = "$argon2id$v=19$m=65536,t=3,p=4$MjQyZWE1MzBjYjJlZTI0Yw$YTU4NGM5ZTZmYjE2NzZlZjY0ZWY3ZGRkY2U2OWFjNjk"


def authenticate(*, session: Session, username: str, password: str) -> User | None:
    db_user = get_user_by_username(session=session, username=username)
    if not db_user:
        verify_password(password, DUMMY_HASH)
        return None
    verified, updated_hash = verify_password(password, db_user.hashed_password)
    if not verified:
        return None
    if updated_hash:  # pwdlib 升级了哈希，回写
        db_user.hashed_password = updated_hash
        session.add(db_user)
        session.commit()
        session.refresh(db_user)
    return db_user


def list_children(*, session: Session, parent_id: uuid.UUID) -> list[User]:
    from sqlmodel import select

    return list(session.exec(select(User).where(User.parent_id == parent_id)))


def update_user(
    *,
    session: Session,
    user: User,
    display_name: str | None = None,
    grade: int | None = None,
    interests: dict | None = None,
) -> User:
    """编辑娃娃资料（WF-5）：仅局部更新昵称/年级/兴趣；账号密码等字段不在此处变动。

    所有字段可选，仅传入非 None 的字段生效。
    """
    if display_name is not None:
        user.display_name = display_name
    if grade is not None:
        user.grade = grade
    if interests is not None:
        user.interests = interests
    session.add(user)
    session.commit()
    session.refresh(user)
    return user
