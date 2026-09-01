"""DELETE /questions 批量删除题库题回归测试。

验证：
  1) 正常：未被任务引用的题被硬删，返回在 deleted；
  2) 被任务引用（TaskQuestion.question_id 存在）的题不删，返回在 skipped_in_use；
  3) 非本家长所有的题不删，返回在 skipped_forbidden（owner 隔离）。
"""
from __future__ import annotations

import uuid

from sqlmodel import Session as DBSession
from sqlmodel import select

from app.core.db import engine
from app.models import Question, Task, TaskQuestion
from tests.utils.user import auth_headers, register_parent


def _parent_id(client, token: str) -> uuid.UUID:
    r = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return uuid.UUID(r.json()["id"])


def test_delete_questions_skips_referenced(client):
    r = register_parent(client, username="del_parent_1")
    ptoken = r.json()["access_token"]
    pid = _parent_id(client, ptoken)

    q_free_id = uuid.uuid4()
    q_used_id = uuid.uuid4()
    with DBSession(engine) as s:
        s.add(Question(
            id=q_free_id, parent_id=pid, subject="数学", grade=2,
            knowledge_point="加法", qtype="calc", stem="1+1=?", answer="2",
            explanation="", difficulty="easy",
        ))
        s.add(Question(
            id=q_used_id, parent_id=pid, subject="语文", grade=2,
            knowledge_point="字词", qtype="fill", stem="填空", answer="x",
            explanation="", difficulty="easy",
        ))
        s.commit()
        task = Task(title="引用任务", status="draft", parent_id=pid)
        s.add(task)
        s.commit()
        s.refresh(task)
        s.add(TaskQuestion(
            task_id=task.id, question_id=q_used_id, subject="语文", grade=2,
            knowledge_point="字词", qtype="fill", stem="填空", answer="x",
            explanation="", difficulty="easy",
        ))
        s.commit()

    r = client.request(
        "DELETE",
        "/api/v1/questions",
        headers=auth_headers(ptoken),
        json={"ids": [str(q_free_id), str(q_used_id)]},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert str(q_free_id) in body["deleted"]
    assert str(q_used_id) in body["skipped_in_use"]

    with DBSession(engine) as s:
        remaining = s.exec(select(Question).where(Question.parent_id == pid)).all()
        remaining_ids = {str(q.id) for q in remaining}
    assert str(q_free_id) not in remaining_ids  # 已硬删
    assert str(q_used_id) in remaining_ids      # 引用中，保留


def test_delete_questions_owner_isolation(client):
    pa = register_parent(client, username="del_parent_a").json()["access_token"]
    pb = register_parent(client, username="del_parent_b").json()["access_token"]
    pida = _parent_id(client, pa)

    q_other_id = uuid.uuid4()
    with DBSession(engine) as s:
        s.add(Question(
            id=q_other_id, parent_id=pida, subject="数学", grade=2,
            knowledge_point="加法", qtype="calc", stem="1+1=?", answer="2",
            explanation="", difficulty="easy",
        ))
        s.commit()

    # 家长 B 删除家长 A 的题 → 不删，归为 skipped_forbidden
    r = client.request(
        "DELETE",
        "/api/v1/questions",
        headers=auth_headers(pb),
        json={"ids": [str(q_other_id)]},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert str(q_other_id) in body["skipped_forbidden"]
    assert str(q_other_id) not in body["deleted"]

    with DBSession(engine) as s:
        assert s.get(Question, q_other_id) is not None  # 仍保留
