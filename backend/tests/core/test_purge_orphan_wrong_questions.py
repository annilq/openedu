"""孤儿错题清理守卫（2026-10-08 修复回归）。

**bug 形状**：``wrongquestion.question_id`` 的 FK 无 ``ON DELETE CASCADE``，且 SQLite
默认不强制外键。源 ``question`` 被硬删（删任务 / 题目再生成 / 批量删题）后，
``wrongquestion`` 行被遗留成 dangling。列表统计（改后）与详情页都 INNER JOIN question，
孤儿既数不到也点不开，造成「数得到点不到」。

本文件在临时库上造出「有有效错题 + 孤儿错题（question_id 为 NULL / 指向不存在的
question）」的形状，直接调用 ``_purge_orphan_wrong_questions`` 守卫，断言：
1. 孤儿被删，有效错题保留；
2. 守卫幂等（连跑多次行数守恒）。
"""
from __future__ import annotations

import sqlite3

from sqlalchemy import create_engine

from app.core.db import _purge_orphan_wrong_questions

_DDL = """
CREATE TABLE question (
    id VARCHAR(36) PRIMARY KEY
);
CREATE TABLE wrongquestion (
    id VARCHAR(36) PRIMARY KEY,
    question_id VARCHAR(36),
    graduated_at TIMESTAMP
);
"""


def _seed(path: str) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(_DDL)
    # 2 条有效错题（question_id 指向存在的 question）
    conn.execute("INSERT INTO question (id) VALUES ('q1'), ('q2')")
    conn.execute(
        "INSERT INTO wrongquestion (id, question_id, graduated_at) VALUES "
        "('w1', 'q1', NULL), ('w2', 'q2', NULL)"
    )
    # 3 条孤儿：1 条 question_id 为 NULL，2 条指向不存在的 question
    conn.execute(
        "INSERT INTO wrongquestion (id, question_id, graduated_at) VALUES "
        "('w_orphan_null', NULL, NULL),"
        "('w_orphan_missing_a', 'ghost1', NULL),"
        "('w_orphan_missing_b', 'ghost2', '2026-10-05 00:00:00')"
    )
    conn.commit()
    conn.close()


def _count(path: str, table: str) -> int:
    conn = sqlite3.connect(path)
    n = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    conn.close()
    return n


def _remaining_question_ids(path: str) -> set[str]:
    conn = sqlite3.connect(path)
    rows = conn.execute("SELECT question_id FROM wrongquestion").fetchall()
    conn.close()
    return {r[0] for r in rows}


def _run_guard(path: str) -> None:
    engine = create_engine(f"sqlite:///{path}")
    with engine.connect() as conn:
        _purge_orphan_wrong_questions(conn)
        conn.commit()


class TestPurgeOrphanWrongQuestions:
    def test_orphans_removed_valid_kept(self, tmp_path):
        db = str(tmp_path / "orphan.db")
        _seed(db)
        assert _count(db, "wrongquestion") == 5

        _run_guard(db)

        # 有效 2 条保留，3 条孤儿全删
        assert _count(db, "wrongquestion") == 2
        assert _remaining_question_ids(db) == {"q1", "q2"}

    def test_guard_is_idempotent(self, tmp_path):
        db = str(tmp_path / "orphan.db")
        _seed(db)
        _run_guard(db)
        # 再跑一次不应再删任何行（幂等）
        _run_guard(db)
        assert _count(db, "wrongquestion") == 2
        # question 表不受牵连
        assert _count(db, "question") == 2
