"""出题流式端点测试（ADR-0015 / 票据 08）：mock 模式下逐题 question 事件 + done。"""
from __future__ import annotations

from tests.utils.sse import parse_sse
from tests.utils.user import auth_headers, login, register_parent


def _parent_token(client, username):
    register_parent(client, username=username, password="pw123456")
    return login(client, username, "pw123456").json()["access_token"]


def test_generate_stream_emits_questions(client):
    ptoken = _parent_token(client, "gs_parent")
    h = auth_headers(ptoken)
    r = client.post(
        "/api/v1/stream/tasks/generate",
        headers=h,
        json={
            "title": "测试卷",
            "specs": [
                {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 2},
                {"subject": "语文", "grade": 3, "knowledge_point": "拼音", "qtype": "choice", "difficulty": "medium", "count": 1},
            ],
        },
    )
    assert r.status_code == 200
    events = parse_sse(r.text)
    types = [e for e, _ in events]
    questions = [d for e, d in events if e == "question"]
    assert len(questions) == 3  # 2 + 1
    assert types[-1] == "done"
    # 每题含必要字段
    for q in questions:
        assert q["subject"] and q["stem"] and "answer" in q


def test_generate_stream_empty_specs_rejected(client):
    ptoken = _parent_token(client, "gs2_parent")
    h = auth_headers(ptoken)
    r = client.post(
        "/api/v1/stream/tasks/generate",
        headers=h,
        json={"title": "空", "specs": []},
    )
    # 校验失败（422）直接返回，不走 SSE
    assert r.status_code == 422
