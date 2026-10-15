"""Conversation.slots 列迁移（ADR-0095）：SQLite 幂等加列 + 读写往返。

对照 ``tests/core/test_kp_semester_unique_migration.py``：在临时库上复现「老库形状」
（conversation 表**没有** slots 列），跑迁移，断言：
1. 列现在存在；
2. 读写往返保真（int/enum/bool/string）；
3. 空 slots → NULL（不存 {} 污染）；
4. 迁移幂等（连跑 3 次，行数守恒）。
"""
from __future__ import annotations

import sqlite3
import uuid

from sqlalchemy import text
from sqlmodel import Session, create_engine

from app.core.db import add_conversation_slots_column
from app.db.models import Conversation

# 老库形状：conversation 表没有 slots 列（本特性上线前的库）。列清单与模型其余列对齐。
_OLD_CONVERSATION_DDL = """
CREATE TABLE conversation (
    id VARCHAR(36) PRIMARY KEY,
    kind VARCHAR(32),
    teacher_id VARCHAR(36),
    student_id VARCHAR(36),
    model VARCHAR(255),
    title VARCHAR(255),
    ref_task_id VARCHAR(36),
    status VARCHAR(16),
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);
"""


def _migrate(db_path: str) -> None:
    engine = create_engine(f"sqlite:///{db_path}")
    with engine.connect() as conn:
        add_conversation_slots_column(conn, is_sqlite=True)
        conn.commit()


def _make_old_db(path: str) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(_OLD_CONVERSATION_DDL)
    conn.commit()
    conn.close()


def _columns(path: str) -> list[str]:
    conn = sqlite3.connect(path)
    cols = [r[1] for r in conn.execute("PRAGMA table_info(conversation)").fetchall()]
    conn.close()
    return cols


class TestConversationSlotsMigration:
    def test_old_db_has_no_slots_column(self, tmp_path):
        """前置：确认造出来的是「老库形状」。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        assert "slots" not in _columns(db)

    def test_migration_adds_slots_column(self, tmp_path):
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _migrate(db)
        assert "slots" in _columns(db)

    def test_roundtrip_preserves_int_enum_bool_string(self, tmp_path):
        """读写往返保真：subject(str) / grade(int) / qtype(str) / count(int) / multi(bool)。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _migrate(db)
        engine = create_engine(f"sqlite:///{db}")
        with Session(engine) as session:
            conv = Conversation(
                kind="question",
                teacher_id=uuid.uuid4(),
                slots={
                    "subject": "数学",
                    "grade": 3,
                    "qtype": "choice",
                    "count": 2,
                    "multi": True,
                },
            )
            session.add(conv)
            session.commit()
            cid = conv.id
        with Session(engine) as session:
            got = session.get(Conversation, cid)
            assert got.slots["subject"] == "数学"
            assert got.slots["grade"] == 3
            assert isinstance(got.slots["grade"], int)
            assert got.slots["qtype"] == "choice"
            assert got.slots["count"] == 2
            assert got.slots["multi"] is True

    def test_empty_slots_stored_as_null_not_empty_object(self, tmp_path):
        """空 slots → SQL NULL（不是 {} 也不是文本 'null'，ADR-0061 纪律）。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _migrate(db)
        engine = create_engine(f"sqlite:///{db}")
        with Session(engine) as session:
            conv = Conversation(kind="question", teacher_id=uuid.uuid4(), slots=None)
            session.add(conv)
            session.commit()
            cid = conv.id
            got = session.get(Conversation, cid)
            assert got is not None
            assert got.slots is None
        # 原始层确认存的是 NULL（不是 {} 也不是文本 'null'）
        raw = sqlite3.connect(db)
        rows = raw.execute("SELECT slots FROM conversation").fetchall()
        raw.close()
        assert rows and rows[0][0] is None, "空 slots 必须存为 NULL"

    def test_migration_is_idempotent(self, tmp_path):
        """幂等：连跑多次不重建、不丢数据（行数守恒）。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _migrate(db)  # 先建列
        engine = create_engine(f"sqlite:///{db}")
        with Session(engine) as session:
            for i in range(2):
                session.add(
                    Conversation(
                        kind="question",
                        teacher_id=uuid.uuid4(),
                        slots={"subject": "语文", "grade": i + 1},
                    )
                )
            session.commit()
        _migrate(db)
        _migrate(db)
        _migrate(db)
        conn = sqlite3.connect(db)
        rows = conn.execute("SELECT COUNT(*) FROM conversation").fetchone()[0]
        conn.close()
        assert rows == 2, "行数必须守恒"
        assert "slots" in _columns(db)

    def test_missing_table_is_noop(self, tmp_path):
        """表还没建时不抛（偏序迁移纪律）。"""
        db = str(tmp_path / "empty.db")
        sqlite3.connect(db).close()
        _migrate(db)  # 不抛即通过
