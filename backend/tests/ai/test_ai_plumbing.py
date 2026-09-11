"""AI 调用归一封装（ADR-0034 Phase 2）契约测试。

锁定两条不变量：
1. ``build_ai_provider`` 统一把 model_ref / parent_id 透传给 ``resolve_engine``，再交
   ``build_provider`` 构造——消除「批改忽略 model」的分裂。
2. 批改调用点（tasks/service 的 answer）确实把 task.model 透传进归一封装。
"""
from __future__ import annotations

import uuid

from sqlmodel import Session

from app.core.ai_plumbing import build_ai_provider
from app.core.db import engine as db_engine
from app.db.models import Task
from tests.utils.fake_provider import FakeLLMProvider
from tests.utils.user import auth_headers, login, register_parent


def test_build_ai_provider_passes_model_ref_through(monkeypatch):
    captured = {}

    def fake_resolve(model_ref=None, *, parent_id=None, session=None):
        captured["model_ref"] = model_ref
        captured["parent_id"] = parent_id
        return "ENGINE"

    def fake_build(engine=None):
        return engine

    monkeypatch.setattr("app.core.ai_plumbing.resolve_engine", fake_resolve)
    monkeypatch.setattr("app.core.ai_plumbing.build_provider", fake_build)

    pid = uuid.uuid4()
    assert build_ai_provider("m1", parent_id=pid) == "ENGINE"
    assert captured["model_ref"] == "m1"
    assert captured["parent_id"] == pid


def test_build_ai_provider_falls_back_to_global(monkeypatch):
    """model_ref 为 None 时回落全局解析（与既有 build_provider() 行为一致）。"""
    captured = {}

    def fake_resolve(model_ref=None, *, parent_id=None, session=None):
        captured["model_ref"] = model_ref
        return None

    monkeypatch.setattr("app.core.ai_plumbing.resolve_engine", fake_resolve)
    monkeypatch.setattr("app.core.ai_plumbing.build_provider", lambda engine=None: "PROV")

    assert build_ai_provider() == "PROV"
    assert captured["model_ref"] is None


def test_grading_passes_task_model_through(monkeypatch, client):
    """批改经归一封装，且把 task.model 透传（模型贯通的核心判据）。"""
    ptoken = register_parent(client, username="aipl_parent").json()["access_token"]
    r = client.post(
        "/api/v1/children",
        headers=auth_headers(ptoken),
        json={
            "username": "aipl_kid",
            "password": "kid123456",
            "display_name": "娃娃",
            "grade": 2,
            "role": "child",
        },
    )
    assert r.status_code == 201, r.text
    child_id = r.json()["id"]

    r = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(ptoken),
        json={
            "title": "grading-model",
            "child_id": child_id,
            "specs": [
                {
                    "subject": "数学",
                    "grade": 2,
                    "knowledge_point": "加法",
                    "qtype": "calc",
                    "difficulty": "easy",
                    "count": 1,
                }
            ],
            "questions": [
                {
                    "subject": "数学",
                    "grade": 2,
                    "knowledge_point": "加法",
                    "qtype": "calc",
                    "difficulty": "easy",
                    "stem": "1 + 1 = ?",
                    "options": None,
                    "answer": "2",
                    "explanation": "1 加 1 等于 2。",
                }
            ],
        },
    )
    assert r.status_code == 201, r.text
    tid = r.json()["id"]

    # 后置写入 task.model（模型贯通的目标值）
    model_ref = "builtin-deepseek-test"
    with Session(db_engine) as s:
        t = s.get(Task, uuid.UUID(tid))
        t.model = model_ref
        s.add(t)
        s.commit()

    client.post(f"/api/v1/tasks/{tid}/confirm", headers=auth_headers(ptoken))
    client.post(
        f"/api/v1/tasks/{tid}/assign",
        headers=auth_headers(ptoken),
        params={"child_id": child_id},
    )

    captured = {}

    def fake_build(model_ref_in=None, *, parent_id=None, session=None):
        captured["model_ref"] = model_ref_in
        return FakeLLMProvider()

    monkeypatch.setattr("app.features.tasks.service.build_ai_provider", fake_build)

    ctoken = login(client, "aipl_kid", "kid123456").json()["access_token"]
    # 草稿期题卡无 source Question.id，answer 端点以 TaskQuestion.id 兜底匹配
    q = r.json()["questions"][0]
    resp = client.post(
        f"/api/v1/tasks/{tid}/answer",
        headers=auth_headers(ctoken),
        json={"question_id": q["id"], "student_answer": "2"},
    )
    assert resp.status_code == 200, resp.text
    assert captured["model_ref"] == model_ref
