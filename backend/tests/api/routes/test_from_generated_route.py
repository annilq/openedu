"""POST /tasks/from-generated 落库回归测试（流式生成 + 落库两步法）。

验证「生成任务」按钮走流式渲染题卡后，把已生成题卡一次性落库为 draft 任务：
  1) 正常：questions 落库为 TaskQuestion，返回 draft 任务且题量一致；
  2) 空 questions → 400（TASK_EMPTY_SPECS）；
  3) child 越权（他人娃娃）→ 403（TASK_CHILD_NOT_OWNED）。
本端点不重新调用出题引擎，直接复用前端流式返回的题卡。
"""
from __future__ import annotations

from tests.utils.user import auth_headers, register_parent


def _create_child(client, ptoken, username="kidfg1"):
    r = client.post(
        "/api/v1/children",
        headers=auth_headers(ptoken),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": "娃娃",
            "grade": 2,
            "role": "child",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


_SAMPLE_QUESTIONS = [
    {
        "subject": "数学",
        "grade": 2,
        "knowledge_point": "加法",
        "qtype": "calc",
        "stem": "计算：1 + 2 = ?",
        "options": None,
        "answer": "3",
        "explanation": "1+2=3",
        "difficulty": "easy",
    },
    {
        "subject": "语文",
        "grade": 2,
        "knowledge_point": "字词",
        "qtype": "fill",
        "stem": "请填空。",
        "options": None,
        "answer": "示例",
        "explanation": "应填写示例。",
        "difficulty": "medium",
    },
]


def test_from_generated_persists_questions(client):
    r = register_parent(client, username="fg_parent_a")
    ptoken = r.json()["access_token"]
    cid = _create_child(client, ptoken, username="fg_kid_a")["id"]

    r = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(ptoken),
        json={
            "title": "流式落库卷",
            "child_id": cid,
            "model": "local-llama",
            "specs": [
                {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 1}
            ],
            "questions": _SAMPLE_QUESTIONS,
        },
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["status"] == "draft"
    assert body["title"] == "流式落库卷"
    assert len(body["questions"]) == 2
    # 题卡内容原样落库（含家长端可见答案）
    stems = {q["stem"] for q in body["questions"]}
    assert "计算：1 + 2 = ?" in stems
    assert body["questions"][0]["answer"] is not None


def test_from_generated_rejects_empty_questions(client):
    r = register_parent(client, username="fg_parent_b")
    ptoken = r.json()["access_token"]
    cid = _create_child(client, ptoken, username="fg_kid_b")["id"]

    r = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(ptoken),
        json={
            "title": "空卷",
            "child_id": cid,
            "specs": [
                {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 1}
            ],
            "questions": [],
        },
    )
    assert r.status_code == 422, r.text


def test_from_generated_rejects_other_child(client):
    pa = register_parent(client, username="fg_parent_c").json()["access_token"]
    pb = register_parent(client, username="fg_parent_d").json()["access_token"]
    cid = _create_child(client, pa, username="fg_kid_c")["id"]

    # 家长 B 试图把题卡挂到家长 A 名下娃娃 → 越权
    r = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(pb),
        json={
            "title": "越权卷",
            "child_id": cid,
            "specs": [
                {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 1}
            ],
            "questions": _SAMPLE_QUESTIONS,
        },
    )
    assert r.status_code == 403, r.text
