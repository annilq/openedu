"""会话归属判据（ADR-0096）：本人可见——教师不看学生的，学生不看同学的。

判据收口在 ``core.guard`` 的三个入口（SQL 过滤 / 单行断言 / 批量过滤），这里直接打
in-memory 库测这**三个入口同源**：任何一处自己拼条件，就会出现「列表能列出、
详情 403 / 删除删不掉」的口径分裂。
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.errors import AppErrorException
from app.core.guard import (
    conversation_owner_clause,
    owned_conversation_ids,
    require_owned_conversation,
)
from app.db.models import Conversation, Role, User


@pytest.fixture()
def session() -> Session:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as s:
        yield s


def _user(role: Role) -> User:
    return User(
        id=uuid.uuid4(),
        username=f"u-{uuid.uuid4().hex[:8]}",
        display_name="某人",
        hashed_password="x",  # noqa: S106 - 测试装置，不涉真实凭据
        role=role,
    )


def _conv(*, teacher_id: uuid.UUID, student_id: uuid.UUID | None) -> Conversation:
    return Conversation(
        kind="query", teacher_id=teacher_id, student_id=student_id, status="done"
    )


def test_teacher_sees_only_own_not_students(session: Session):
    """教师口径：``teacher_id == me AND student_id IS NULL``——学生的会话看不到。"""
    teacher = _user(Role.TEACHER)
    student = _user(Role.STUDENT)
    student.teacher_id = teacher.id
    session.add(teacher)
    session.add(student)

    mine = _conv(teacher_id=teacher.id, student_id=None)
    kid = _conv(teacher_id=teacher.id, student_id=student.id)
    session.add(mine)
    session.add(kid)
    session.commit()

    rows = session.exec(
        select(Conversation).where(conversation_owner_clause(teacher))
    ).all()
    assert [c.id for c in rows] == [mine.id]


def test_student_sees_only_self(session: Session):
    """学生口径：``student_id == me``——教师与同学的会话都看不到。"""
    teacher = _user(Role.TEACHER)
    a = _user(Role.STUDENT)
    b = _user(Role.STUDENT)
    session.add_all([teacher, a, b])

    own = _conv(teacher_id=teacher.id, student_id=a.id)
    peer = _conv(teacher_id=teacher.id, student_id=b.id)
    teachers = _conv(teacher_id=teacher.id, student_id=None)
    session.add_all([own, peer, teachers])
    session.commit()

    assert owned_conversation_ids(
        session=session, user=a, ids=[own.id, peer.id, teachers.id]
    ) == [own.id]


def test_admin_uses_teacher_branch_own_only(session: Session):
    """admin 复用 teacher 面（ADR-0088）：也只看自己聊的。"""
    admin = _user(Role.ADMIN)
    session.add(admin)
    mine = _conv(teacher_id=admin.id, student_id=None)
    other = _conv(teacher_id=uuid.uuid4(), student_id=None)
    session.add_all([mine, other])
    session.commit()

    assert owned_conversation_ids(session=session, user=admin, ids=[mine.id, other.id]) == [
        mine.id
    ]


def test_require_owned_conversation_matches_list_filter(session: Session):
    """同一会话：列表判据说「不是我的」时，详情必须 403（不是 404）。"""
    teacher = _user(Role.TEACHER)
    student = _user(Role.STUDENT)
    session.add_all([teacher, student])
    kid = _conv(teacher_id=teacher.id, student_id=student.id)
    session.add(kid)
    session.commit()

    with pytest.raises(AppErrorException):
        require_owned_conversation(session=session, user=teacher, conv_id=kid.id)

    # 学生自己能拿到——同一行，两种归属结果
    got = require_owned_conversation(session=session, user=student, conv_id=kid.id)
    assert got.id == kid.id


def test_require_owned_conversation_missing_id_is_forbidden(session: Session):
    """不存在与不属于抛同一个错：不把越权降级成「不存在」。"""
    with pytest.raises(AppErrorException):
        require_owned_conversation(
            session=session, user=_user(Role.TEACHER), conv_id=uuid.uuid4()
        )


def test_owned_conversation_ids_empty_input(session: Session):
    assert owned_conversation_ids(session=session, user=_user(Role.TEACHER), ids=[]) == []
