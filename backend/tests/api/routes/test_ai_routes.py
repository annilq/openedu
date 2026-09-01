"""AI 统一端点（迁移 08b / ADR-0015）原生 Genkit wire 格式单测。

验证薄路由层（auth + 使用管控 + 输入安全）委托给 flow 后，返回**原生**
Genkit 线格式：一次性 `{"result": ...}` 与 SSE 流式 `data: {"message":..}` /
`data: {"result":..}`，可被前端 package:genkit client.dart 的 defineRemoteAction 直连。

mock 模式：测试环境无真实模型（resolve_engine 返回 None），flow 走「一次性模拟
数据源」分支，产出确定性假数据，闭环跑通且无需外部依赖。
"""
from tests.utils.user import auth_headers, login, register_parent


def _setup(client, parent_u, child_u):
    pr = register_parent(client, username=parent_u)
    assert pr.status_code == 200
    ptoken = pr.json()["access_token"]
    r = client.post(
        "/api/v1/children",
        headers=auth_headers(ptoken),
        json={
            "username": child_u,
            "password": "kid123456",
            "display_name": "娃娃",
            "grade": 3,
            "role": "child",
        },
    )
    assert r.status_code == 201, r.text
    child = r.json()
    lr = login(client, child_u, "kid123456")
    assert lr.status_code == 200
    ctoken = lr.json()["access_token"]
    return ptoken, child, ctoken


def test_ai_tutor_ask_native_result_envelope(client):
    """/ai/tutor/ask 一次性结果：返回 {'result': {'text','blocked','reason'}} 并落库。"""
    _ptoken, child, ctoken = _setup(client, "ai1_parent", "ai1_kid")
    r = client.post(
        "/api/v1/ai/tutor/ask",
        headers=auth_headers(ctoken),
        json={
            "data": {
                "subject": "数学",
                "grade": 3,
                "knowledge_point": "减法",
                "question": "怎么算 100 - 37",
            }
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    # 原生线格式：result 包裹 TutorReply（genkit to_dict 省略 None 字段，reason 可能缺省）
    assert "result" in body
    reply = body["result"]
    assert reply["blocked"] is False
    assert reply.get("reason") is None
    assert "减法" in reply["text"]

    # 日志落库（flow 内 _log_tutor）
    logs = client.get(
        "/api/v1/tutor/logs",
        headers=auth_headers(_ptoken),
        params={"child_id": child["id"]},
    )
    assert logs.status_code == 200
    assert len(logs.json()) == 1
    assert logs.json()[0]["blocked"] is False


def test_ai_tutor_ask_streaming_sse(client):
    """/ai/tutor/ask 流式：Accept text/event-stream → SSE 含 message 帧 + result 帧。"""
    _ptoken, _child, ctoken = _setup(client, "ai2_parent", "ai2_kid")
    with client.stream(
        "POST",
        "/api/v1/ai/tutor/ask",
        headers={**auth_headers(ctoken), "Accept": "text/event-stream"},
        json={
            "data": {
                "subject": "语文",
                "grade": 3,
                "knowledge_point": "拼音",
                "question": "b 和 p 怎么区分",
            }
        },
    ) as r:
        assert r.status_code == 200, r.status_code
        text = "".join(r.iter_text())
    assert 'data: {"message":' in text, "缺少流式 message 帧"
    assert 'data: {"result":' in text, "缺少流式 result 帧"
    # 末帧 result 应为 TutorReply dict
    assert '"blocked":false' in text or '"blocked": false' in text


def test_ai_tasks_generate_native_result_list(client):
    """/ai/tasks/generate：返回 {'result': [QuestionOut,...]}，题量与 specs 一致（mock）。"""
    _ptoken, child, ctoken = _setup(client, "ai3_parent", "ai3_kid")
    r = client.post(
        "/api/v1/ai/tasks/generate",
        headers=auth_headers(_ptoken),
        json={
            "data": {
                "child_id": child["id"],
                "specs": [
                    {
                        "subject": "数学",
                        "grade": 3,
                        "knowledge_point": "乘法",
                        "qtype": "calc",
                        "difficulty": "easy",
                        "count": 2,
                    },
                    {
                        "subject": "语文",
                        "grade": 3,
                        "knowledge_point": "词语",
                        "qtype": "fill",
                        "count": 1,
                    },
                ],
                "model": None,
            }
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert "result" in body
    questions = body["result"]
    assert isinstance(questions, list)
    assert len(questions) == 3  # 2 + 1
    for q in questions:
        assert q["subject"] and q["knowledge_point"] and q["answer"]
        assert "stem" in q and "explanation" in q


def test_ai_tutor_ask_quota_429(client):
    """使用管控：家长设每日上限 0 → 答疑 429（路由器前置校验生效）。"""
    ptoken, child, ctoken = _setup(client, "ai4_parent", "ai4_kid")
    # 家长配置该娃娃每日答疑上限为 0
    set_q = client.put(
        "/api/v1/tutor/quota",
        headers=auth_headers(ptoken),
        params={"child_id": child["id"]},
        json={"daily_ask_limit": 0},
    )
    assert set_q.status_code == 200, set_q.text
    r = client.post(
        "/api/v1/ai/tutor/ask",
        headers=auth_headers(ctoken),
        json={
            "data": {
                "subject": "数学",
                "grade": 3,
                "knowledge_point": "加法",
                "question": "1+1",
            }
        },
    )
    assert r.status_code == 429, r.text
