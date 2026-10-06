"""知识点不允许空学期迁移（2026-10-05 决策）回归。

复现「整学年('') 与具体学期并存」的老库形状，跑迁移，断言：
1. 同一概念同时有 '' 行与具体学期行 → '' 行被删（具体学期胜出）；
2. 纯整学年 '' 行 → 改为 '上学期'；
3. 既有具体学期行不受影响；
4. 迁移后全表无 '' 行；
5. 幂等：连跑多次不丢数据、不报错。
"""
from __future__ import annotations

import sqlite3

from sqlmodel import create_engine

from app.core.db import _migrate_kp_no_empty_semester

_DDL = """
CREATE TABLE knowledgepoint (
    id CHAR(32) NOT NULL,
    teacher_id CHAR(32) NOT NULL,
    subject VARCHAR(16) NOT NULL,
    grade INTEGER NOT NULL,
    name VARCHAR(128) NOT NULL,
    status VARCHAR(16) NOT NULL,
    source VARCHAR(16) NOT NULL,
    created_at DATETIME,
    semester VARCHAR(8) DEFAULT '上学期',
    scenes TEXT,
    PRIMARY KEY (id),
    UNIQUE (teacher_id, subject, grade, name, semester)
);
"""


def _make_db(path: str) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(_DDL)
    # X：'' 行(已转正) + 上学期行(待审) —— 重名并存，'' 应被删
    conn.execute(
        "INSERT INTO knowledgepoint "
        "(id,teacher_id,subject,grade,name,status,source,created_at,semester,scenes) "
        "VALUES ('x0','p1','数学',4,'图形的运动','curated','skeleton','2026-10-05','',NULL)"
    )
    conn.execute(
        "INSERT INTO knowledgepoint "
        "(id,teacher_id,subject,grade,name,status,source,created_at,semester,scenes) "
        "VALUES ('x1','p1','数学',4,'图形的运动','pending','emerged','2026-10-05','上学期',NULL)"
    )
    # Y：仅 '' 行（纯整学年）→ 改上学期
    conn.execute(
        "INSERT INTO knowledgepoint "
        "(id,teacher_id,subject,grade,name,status,source,created_at,semester,scenes) "
        "VALUES ('y0','p1','语文',3,'记叙文','pending','emerged','2026-10-05','',NULL)"
    )
    # Z：仅具体学期行，无 '' → 不受影响
    conn.execute(
        "INSERT INTO knowledgepoint "
        "(id,teacher_id,subject,grade,name,status,source,created_at,semester,scenes) "
        "VALUES ('z0','p1','英语',5,'时态','curated','skeleton','2026-10-05','下学期',NULL)"
    )
    conn.commit()
    conn.close()


def _rows(path: str) -> dict:
    conn = sqlite3.connect(path)
    out = {
        r[0]: {"name": r[1], "status": r[2], "semester": r[3]}
        for r in conn.execute(
            "SELECT id, name, status, semester FROM knowledgepoint ORDER BY id"
        ).fetchall()
    }
    conn.close()
    return out


def _run(path: str) -> None:
    engine = create_engine(f"sqlite:///{path}")
    with engine.connect() as conn:
        _migrate_kp_no_empty_semester(conn)
        conn.commit()


class TestNoEmptySemesterMigration:
    def test_removes_overlapping_empty_and_flips_pure_year(self, tmp_path):
        db = str(tmp_path / "kp.db")
        _make_db(db)
        _run(db)
        rows = _rows(db)
        # X 的 '' 行被删，仅剩上学期(pending)
        assert "x0" not in rows
        assert rows["x1"] == {
            "name": "图形的运动",
            "status": "pending",
            "semester": "上学期",
        }
        # Y 的 '' 改为上学期，状态/其它不变
        assert rows["y0"] == {
            "name": "记叙文",
            "status": "pending",
            "semester": "上学期",
        }
        # Z 不受影响
        assert rows["z0"] == {
            "name": "时态",
            "status": "curated",
            "semester": "下学期",
        }
        # 全表无空学期
        assert all(r["semester"] for r in rows.values())

    def test_idempotent(self, tmp_path):
        db = str(tmp_path / "kp.db")
        _make_db(db)
        _run(db)
        _run(db)
        _run(db)
        rows = _rows(db)
        assert len(rows) == 3  # 行数守恒：x0 删、其余三保留
        assert all(r["semester"] for r in rows.values())

    def test_missing_table_is_noop(self, tmp_path):
        db = str(tmp_path / "empty.db")
        sqlite3.connect(db).close()
        _run(db)  # 不抛即通过
