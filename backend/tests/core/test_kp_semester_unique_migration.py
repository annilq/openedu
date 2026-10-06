"""知识点唯一约束必须含 ``semester``（ADR-0061 §R 回归）。

**这个 bug 的形状很特别**：加学期维度那次迁移只补了**列**
（``ALTER TABLE knowledgepoint ADD COLUMN semester``），但 SQLite **没有**
``ALTER TABLE ... ADD CONSTRAINT`` —— ``ADD COLUMN`` 里写的 ``UNIQUE(...)``
子句会被**静默忽略**。于是任何在加学期维度**之前**建库的库（含本机开发库）
唯一约束仍是旧的 4 列 ``UNIQUE(teacher_id, subject, grade, name)``。

后果不是「报错」而是**静默废掉 §J 承诺的核心能力**：同一知识点按学期各存一份
（上/下学期各一份模板）根本存不进去 —— 名字一撞就撞唯一约束。

所以本文件直接**在临时库上复现「老库形状」**（4 列约束），跑迁移，断言：
1. 约束变成 5 列；
2. 同一 name 在不同 semester 下能共存（迁移前必抛 IntegrityError）；
3. 迁移幂等（连跑多次不重复重建、行数守恒）。
"""
from __future__ import annotations

import sqlite3

import pytest
from sqlmodel import create_engine

from app.core.db import _rebuild_kp_unique_with_semester

# 老库形状：4 列唯一约束（**没有** semester），列齐全。
_OLD_DDL = """
CREATE TABLE knowledgepoint (
    id CHAR(32) NOT NULL,
    teacher_id CHAR(32) NOT NULL,
    subject VARCHAR(16) NOT NULL,
    grade INTEGER NOT NULL,
    name VARCHAR(128) NOT NULL,
    status VARCHAR(16) NOT NULL,
    source VARCHAR(16) NOT NULL,
    created_at DATETIME,
    semester VARCHAR(8) DEFAULT '',
    scenes TEXT,
    PRIMARY KEY (id),
    UNIQUE (teacher_id, subject, grade, name),
    FOREIGN KEY(teacher_id) REFERENCES user (id)
);
CREATE INDEX ix_knowledgepoint_scope
    ON knowledgepoint (teacher_id, subject, grade);
"""


def _migrate(db_path: str) -> None:
    """跑迁移。函数内部用 ``text(...)``，所以必须喂 SQLAlchemy 连接。"""
    engine = create_engine(f"sqlite:///{db_path}")
    with engine.connect() as conn:
        _rebuild_kp_unique_with_semester(conn)
        conn.commit()


def _make_old_db(path: str) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(_OLD_DDL)
    conn.commit()
    conn.close()


def _insert_kp(path: str, *, name: str, semester: str, kp_id: str = "k1") -> None:
    conn = sqlite3.connect(path)
    conn.execute(
        "INSERT INTO knowledgepoint "
        "(id, teacher_id, subject, grade, name, status, source, created_at, semester, scenes)"
        " VALUES (?, 'p1', '数学', 4, ?, 'curated', 'skeleton', '2026-10-05', ?, NULL)",
        (kp_id, name, semester),
    )
    conn.commit()
    conn.close()


def _unique_cols(path: str) -> list[str]:
    """从 sqlite_master 读出 UNIQUE 约束的列名列表。"""
    conn = sqlite3.connect(path)
    ddl = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='knowledgepoint'"
    ).fetchone()[0]
    conn.close()
    tail = ddl.upper().split("UNIQUE", 1)[1]
    inner = tail[tail.index("(") + 1 : tail.index(")")]
    return [c.strip().lower() for c in inner.split(",")]


def _index_cols(path: str) -> list[str]:
    conn = sqlite3.connect(path)
    sql = conn.execute(
        "SELECT sql FROM sqlite_master WHERE name='ix_knowledgepoint_scope'"
    ).fetchone()[0]
    conn.close()
    inner = sql[sql.index("(") + 1 : sql.rindex(")")]
    return [c.strip().lower() for c in inner.split(",")]


class TestStaleUniqueConstraint:
    def test_old_db_has_four_column_constraint(self, tmp_path):
        """前置：确认我们造出来的确实是「老库形状」（否则下面测不出东西）。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        assert _unique_cols(db) == ["teacher_id", "subject", "grade", "name"]

    def test_old_db_cannot_hold_same_name_across_semesters(self, tmp_path):
        """**复现原 bug**：老约束下同一 name 换学期就撞唯一约束。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _insert_kp(db, name="图形的运动（轴对称）", semester="下学期", kp_id="k1")
        with pytest.raises(sqlite3.IntegrityError):
            _insert_kp(db, name="图形的运动（轴对称）", semester="上学期", kp_id="k2")

    def test_migration_adds_semester_to_constraint(self, tmp_path):
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _migrate(db)
        assert _unique_cols(db) == [
            "teacher_id",
            "subject",
            "grade",
            "name",
            "semester",
        ]

    def test_migration_rebuilds_scope_index_with_semester(self, tmp_path):
        """旧库那条 scope 索引只有 3 列，迁移后应是 4 列。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _migrate(db)
        assert _index_cols(db) == ["teacher_id", "subject", "grade", "semester"]

    def test_after_migration_same_name_coexists_across_semesters(self, tmp_path):
        """**核心断言**：迁移后 §J 承诺的能力才真正成立。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _insert_kp(db, name="图形的运动（轴对称）", semester="下学期", kp_id="k1")
        _migrate(db)
        # 迁移前这里会抛 IntegrityError
        _insert_kp(db, name="图形的运动（轴对称）", semester="上学期", kp_id="k2")
        _insert_kp(db, name="图形的运动（轴对称）", semester="", kp_id="k3")
        conn = sqlite3.connect(db)
        rows = conn.execute(
            "SELECT semester FROM knowledgepoint ORDER BY kp_id" if False else
            "SELECT semester FROM knowledgepoint ORDER BY id"
        ).fetchall()
        conn.close()
        assert len(rows) == 3

    def test_duplicate_within_same_semester_still_rejected(self, tmp_path):
        """补上 semester 不等于放弃唯一性：同学期同名字仍必须被拒。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _migrate(db)
        _insert_kp(db, name="图形的运动（轴对称）", semester="上学期", kp_id="k1")
        with pytest.raises(sqlite3.IntegrityError):
            _insert_kp(db, name="图形的运动（轴对称）", semester="上学期", kp_id="k2")

    def test_migration_is_idempotent(self, tmp_path):
        """幂等：连跑多次不重复重建、不丢数据。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        _insert_kp(db, name="A", semester="上学期", kp_id="k1")
        _insert_kp(db, name="B", semester="下学期", kp_id="k2")
        _migrate(db)
        _migrate(db)
        _migrate(db)
        conn = sqlite3.connect(db)
        rows = conn.execute("SELECT COUNT(*) FROM knowledgepoint").fetchone()[0]
        conn.close()
        assert rows == 2, "行数必须守恒"
        assert _unique_cols(db)[-1] == "semester"

    def test_migration_preserves_scenes_column(self, tmp_path):
        """重建表不能丢 scenes（教师配的讲解模板会整列消失）。"""
        db = str(tmp_path / "old.db")
        _make_old_db(db)
        conn = sqlite3.connect(db)
        conn.execute(
            "INSERT INTO knowledgepoint "
            "(id, teacher_id, subject, grade, name, status, source, created_at, semester, scenes)"
            " VALUES ('k1','p1','数学',4,'A','curated','skeleton','2026-10-05','上学期',?)",
            ('[{"kind":"reflection"}]',),
        )
        conn.commit()
        conn.close()
        _migrate(db)
        conn = sqlite3.connect(db)
        row = conn.execute("SELECT scenes FROM knowledgepoint WHERE id='k1'").fetchone()
        conn.close()
        assert row[0] == '[{"kind":"reflection"}]'

    def test_missing_table_is_noop(self, tmp_path):
        """表还没建时不应抛（偏序迁移的纪律）。"""
        db = str(tmp_path / "empty.db")
        sqlite3.connect(db).close()
        _migrate(db)  # 不抛即通过
