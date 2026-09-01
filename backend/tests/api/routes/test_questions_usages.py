from __future__ import annotations

import uuid

from sqlmodel import Session as DBSession

from app.core.db import engine
from app.models import Question, Task, TaskQuestion
from tests.utils.user import auth_headers, register_parent


def _parent_id(client, token: str) -> uuid.UUID:
    r = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return uuid.UUID(r.json()["id"])


def _seed_usage(pid: uuid.UUID):
    """落库一道被两道任务引用的题 + 一道未引用的题，返回各自 id。"""
    q_used_id = uuid.uuid4()
    q_free_id = uuid.uuid4()
    task_a_id = uuid.uuid4()
    task_b_id = uuid.uuid4()
    with DBSession(engine) as s:
        s.add(Question(
            id=q_used_id, parent_id=pid, subject="数学", grade=2,
            knowledge_point="加法", qtype="calc", stem="1+1=?", answer="2",
            explanation="", difficulty="easy",
        ))
        s.add(Question(
            id=q_free_id, parent_id=pid, subject="语文", grade=2,
            knowledge_point="字词", qtype="fill", stem="填空", answer="x",
            explanation="", difficulty="easy",
        ))
        s.add(Task(id=task_a_id, title="引用任务A", status="draft", parent_id=pid))
        s.add(Task(id=task_b_id, title="引用任务B", status="assigned", parent_id=pid))
        s.commit()
        s.add(TaskQuestion(
            task_id=task_a_id, question_id=q_used_id, subject="数学", grade=2,
            knowledge_point="加法", qtype="calc", stem="1+1=?", answer="2",
            explanation="", difficulty="easy",
        ))
        s.add(TaskQuestion(
            task_id=task_b_id, question_id=q_used_id, subject="数学", grade=2,
            knowledge_point="加法", qtype="calc", stem="1+1=?", answer="2",
            explanation="", difficulty="easy",
        ))
        s.commit()
    return q_used_id, q_free_id


def test_usages_lists_referencing_tasks(client):
    r = register_parent(client, username="use_parent_1")
    ptoken = r.json()["access_token"]
    pid = _parent_id(client, ptoken)
    q_used_id, q_free_id = _seed_usage(pid)

    r = client.get(
        f"/api/v1/questions/{q_used_id}/usages",
        headers=auth_headers(ptoken),
    )
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    assert len(items) == 2
    assert {"引用任务A", "引用任务B"} == {it["title"] for it in items}

    # 未被引用的题 → 空列表
    r2 = client.get(
        f"/api/v1/questions/{q_free_id}/usages",
        headers=auth_headers(ptoken),
    )
    assert r2.status_code == 200, r2.text
    assert r2.json()["items"] == []


def test_usages_forbidden_for_other_parent(client):
    ra = register_parent(client, username="use_parent_a")
    rtoken = ra.json()["access_token"]
    rid = _parent_id(client, rtoken)
    rb = register_parent(client, username="use_parent_b")
    btoken = rb.json()["access_token"]

    q_id = uuid.uuid4()
    with DBSession(engine) as s:
        s.add(Question(
            id=q_id, parent_id=rid, subject="数学", grade=2,
            knowledge_point="加法", qtype="calc", stem="1+1=?", answer="2",
            explanation="", difficulty="easy",
        ))
        s.commit()

    # 家长 B 查询家长 A 的题 → 403
    r = client.get(
        f"/api/v1/questions/{q_id}/usages",
        headers=auth_headers(btoken),
    )
    assert r.status_code == 403, r.text
