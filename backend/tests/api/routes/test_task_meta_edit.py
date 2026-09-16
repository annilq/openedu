"""PUT /tasks/{task_id} 元信息编辑端点测试（仅 draft 态，当前仅 title）。

场景来源：家长生成草稿后发现卷名起错（「今日练习」→ 想改成具体日期/主题），
此前没有任务级编辑端点，只能作废重来（生成一次要等 LLM）。审核页逐题编辑
（R-Q4）不覆盖任务标题，故补本端点——与逐题编辑同一套「归属 + draft 态」校验。
"""
from __future__ import annotations

import uuid

import pytest
from sqlmodel import Session as DBSession

from app.core.db import engine
from app.db.models import Task
from tests.utils.user import auth_headers, register_parent

TASK_URL = "/api/v1/tasks"


@pytest.fixture
def parent_token(client):
    username = f"meta_parent_{uuid.uuid4().hex[:8]}"
    r = register_parent(client, username=username)
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def _seed_task(parent_id: uuid.UUID, *, status: str = "draft", title: str = "今日练习") -> uuid.UUID:
    task_id = uuid.uuid4()
    with DBSession(engine) as s:
        s.add(
            Task(
                id=task_id,
                parent_id=parent_id,
                title=title,
                status=status,
                child_id=None,
            )
        )
        s.commit()
    return task_id


def _me_id(client, token: str) -> uuid.UUID:
    me = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert me.status_code == 200, me.text
    return uuid.UUID(me.json()["id"])


def test_edit_title_on_draft(client, parent_token):
    """草稿态改标题：200 且新标题落库。"""
    tid = _seed_task(_me_id(client, parent_token))

    r = client.put(
        f"{TASK_URL}/{tid}",
        headers=auth_headers(parent_token),
        json={"title": "周三数学小测"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["title"] == "周三数学小测"
    assert body["status"] == "draft"

    # GET 回读确认已持久化
    r = client.get(f"{TASK_URL}/{tid}", headers=auth_headers(parent_token))
    assert r.status_code == 200, r.text
    assert r.json()["title"] == "周三数学小测"


def test_edit_title_rejected_when_not_draft(client, parent_token):
    """ready 态不可改标题（409 / TASK_20004）——锁定成卷后标题随卷固定。"""
    tid = _seed_task(_me_id(client, parent_token), status="ready")

    r = client.put(
        f"{TASK_URL}/{tid}",
        headers=auth_headers(parent_token),
        json={"title": "改名"},
    )
    assert r.status_code == 409, r.text
    assert r.json()["code"] == "TASK_20004"


def test_edit_title_other_parents_task_404(client, parent_token):
    """越权伪装成不存在：别人的任务 404（与 _owned_task 对外契约一致）。"""
    other = register_parent(client, username=f"other_{uuid.uuid4().hex[:8]}")
    other_token = other.json()["access_token"]
    tid = _seed_task(_me_id(client, other_token))

    r = client.put(
        f"{TASK_URL}/{tid}",
        headers=auth_headers(parent_token),
        json={"title": "偷改"},
    )
    assert r.status_code == 404, r.text


def test_edit_title_overlong_rejected(client, parent_token):
    """标题超长（>255）422：与创建端点（TaskFromGenerated）同一约束。"""
    tid = _seed_task(_me_id(client, parent_token))

    r = client.put(
        f"{TASK_URL}/{tid}",
        headers=auth_headers(parent_token),
        json={"title": "长" * 256},
    )
    assert r.status_code == 422, r.text
