"""POST /tasks/from-generated 落库回归测试（流式生成 + 落库两步法）。

验证「生成任务」按钮走流式渲染题卡后，把已生成题卡一次性落库为 draft 任务：
  1) 正常：questions 落库为 TaskQuestion，返回 draft 任务且题量一致；
  2) 空 questions → 400（TASK_EMPTY_SPECS）；
  3) child 越权（他人娃娃）→ 403（TASK_CHILD_NOT_OWNED）。
本端点不重新调用出题引擎，直接复用前端流式返回的题卡。
"""
from __future__ import annotations

import uuid

from sqlmodel import select

from app.db.models.task import TaskQuestion
from app.features.tasks import service as tasks_service
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


# ───────────────────── 不变量：reasoning（出题思路）永不落库 ─────────────────────
# ADR-0056：QuestionOut.reasoning 仅用于流式预览态展示，不落库。
# /tasks/from-generated 落库端点不论入参是否带 reasoning，都必须成功，且落库结果
# 里不能有任何 reasoning 痕迹（不写进 TaskQuestion 表、也不出现在响应里）。


def _questions_with_reasoning() -> list[dict]:
    qs = [dict(q) for q in _SAMPLE_QUESTIONS]
    for i, q in enumerate(qs):
        q["reasoning"] = f"这是第 {i + 1} 题的出题思路，仅用于预览，不应落库。"
    return qs


def test_from_generated_without_reasoning_succeeds(client):
    """基线：入参不含 reasoning 字段时，正常落库成功。"""
    r = register_parent(client, username="fg_parent_nr").json()["access_token"]
    cid = _create_child(client, r, username="fg_kid_nr")["id"]

    resp = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(r),
        json={
            "title": "无 reasoning 卷",
            "child_id": cid,
            "specs": [
                {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 1}
            ],
            "questions": _SAMPLE_QUESTIONS,
        },
    )
    assert resp.status_code == 201, resp.text


def test_from_generated_with_reasoning_drops_it(client, db):
    """重点：入参带 reasoning（模拟前端把预览题原样回传）→ 落库成功，
    且 reasoning 被白名单丢弃，不写进 TaskQuestion 表、也不出现在响应里。"""
    r = register_parent(client, username="fg_parent_r").json()["access_token"]
    cid = _create_child(client, r, username="fg_kid_r")["id"]

    resp = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(r),
        json={
            "title": "含 reasoning 卷",
            "child_id": cid,
            "specs": [
                {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 1}
            ],
            "questions": _questions_with_reasoning(),
        },
    )
    # 不能为了让「不该存」成立而让整个请求 400/失败。
    assert resp.status_code == 201, resp.text
    body = resp.json()

    # 响应层：落库返回的题目里不能出现 reasoning 键。
    assert len(body["questions"]) == 2
    for q in body["questions"]:
        assert "reasoning" not in q, q

    # 库表层：直接读 TaskQuestion 行，确认 reasoning 没进表。
    task_id = uuid.UUID(body["id"])
    rows = db.exec(select(TaskQuestion).where(TaskQuestion.task_id == task_id)).all()
    assert len(rows) == 2
    for row in rows:
        dumped = row.model_dump()
        assert "reasoning" not in dumped, dumped


def test_question_fields_whitelist_drops_reasoning():
    """锁住 _question_fields 白名单：reasoning 必须被排除。"""
    payload = {
        "subject": "数学",
        "grade": 2,
        "knowledge_point": "加法",
        "qtype": "calc",
        "stem": "1+2=?",
        "options": None,
        "answer": "3",
        "explanation": "1+2=3",
        "difficulty": "easy",
        "reasoning": "不应被采集的出题思路",
        "ai_note": "也不该以别的名字落库",
    }
    fields = tasks_service._question_fields(payload)
    assert "reasoning" not in fields
    assert "ai_note" not in fields
