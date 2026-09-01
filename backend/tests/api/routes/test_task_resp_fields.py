"""GET /tasks 响应应携带 child_id / created_at（任务列表展示“对应娃娃”与排序）。"""
from __future__ import annotations

import uuid

from sqlmodel import Session as DBSession

from app.core.db import engine
from app.models import Task
from tests.utils.user import auth_headers, register_parent

TASK_URL = "/api/v1/tasks"


def test_task_list_includes_child_id_and_created_at(client):
    r = register_parent(client, username="resp_parent_1")
    ptoken = r.json()["access_token"]
    me = client.get("/api/v1/auth/me", headers=auth_headers(ptoken))
    assert me.status_code == 200, me.text
    pid = uuid.UUID(me.json()["id"])

    task_id = uuid.uuid4()
    with DBSession(engine) as s:
        s.add(
            Task(
                id=task_id,
                parent_id=pid,
                title="一年级数学小测",
                status="draft",
                child_id=None,
            )
        )
        s.commit()

    r = client.get(TASK_URL, headers=auth_headers(ptoken))
    assert r.status_code == 200, r.text
    body = r.json()
    assert isinstance(body, list) and body, "GET /tasks 应返回非空列表"
    item = next(t for t in body if t["id"] == str(task_id))
    # 新字段必须序列化（之前缺失，导致前端无法展示“对应娃娃”与日期）
    assert "child_id" in item
    assert "created_at" in item
    assert item["child_id"] is None  # 草稿可未派发
    assert item["created_at"] is not None
