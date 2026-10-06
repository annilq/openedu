"""GET /tasks 响应应携带 student_id / created_at（任务列表展示“对应学生”与排序）。"""
from __future__ import annotations

import uuid

from sqlmodel import Session as DBSession

from app.core.db import engine
from app.db.models import Task
from tests.utils.paging import page_items
from tests.utils.user import auth_headers, register_teacher

TASK_URL = "/api/v1/tasks"


def test_task_list_includes_student_id_and_created_at(client):
    r = register_teacher(client, username="resp_teacher_1")
    ptoken = r.json()["access_token"]
    me = client.get("/api/v1/auth/me", headers=auth_headers(ptoken))
    assert me.status_code == 200, me.text
    pid = uuid.UUID(me.json()["id"])

    task_id = uuid.uuid4()
    with DBSession(engine) as s:
        s.add(
            Task(
                id=task_id,
                teacher_id=pid,
                title="一年级数学小测",
                status="draft",
                student_id=None,
            )
        )
        s.commit()

    r = client.get(TASK_URL, headers=auth_headers(ptoken))
    assert r.status_code == 200, r.text
    items = page_items(r)
    assert items, "GET /tasks 应返回非空列表"
    item = next(t for t in items if t["id"] == str(task_id))
    # 新字段必须序列化（之前缺失，导致前端无法展示“对应学生”与日期）
    assert "student_id" in item
    assert "created_at" in item
    assert item["student_id"] is None  # 草稿可未派发
    assert item["created_at"] is not None
