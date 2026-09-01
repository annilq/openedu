"""出题流式端点测试（迁移 08b / 统一 Genkit 全栈）：mock 模式下逐题 message 块 + result 末帧。

请求体须用 Genkit action 信封 `{"data": {...}}`；流式响应用 client.stream 读取完整 SSE。
"""
from __future__ import annotations

from tests.utils.sse import parse_genkit_sse
from tests.utils.user import auth_headers, login, register_parent


def _parent_token(client, username):
    register_parent(client, username=username, password="pw123456")
    return login(client, username, "pw123456").json()["access_token"]


def test_generate_stream_emits_questions(client):
    ptoken = _parent_token(client, "gs_parent")
    h = auth_headers(ptoken)
    with client.stream(
        "POST",
        "/api/v1/ai/tasks/generate",
        headers={**h, "Accept": "text/event-stream"},
        json={
            "data": {
                "specs": [
                    {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 2},
                    {"subject": "语文", "grade": 3, "knowledge_point": "拼音", "qtype": "choice", "difficulty": "medium", "count": 1},
                ],
            }
        },
    ) as r:
        assert r.status_code == 200, r.status_code
        text = "".join(r.iter_text())
    chunks, result = parse_genkit_sse(text)
    # 每题一张卡（2 + 1）
    assert len(chunks) == 3
    # 末帧整卷
    assert result is not None and len(result) == 3
    for q in chunks:
        assert q["subject"] and q["stem"] and "answer" in q


def test_generate_stream_invalid_spec_rejected(client):
    ptoken = _parent_token(client, "gs2_parent")
    h = auth_headers(ptoken)
    with client.stream(
        "POST",
        "/api/v1/ai/tasks/generate",
        headers={**h, "Accept": "text/event-stream"},
        # 缺 grade/knowledge_point/qtype → 输入 schema 校验失败（genkit 把校验错误作为
        # 流式 error 帧透传，故 HTTP 200 但 parse_genkit_sse 抛错；或直接 4xx）。
        json={"data": {"specs": [{"subject": "数学"}]}},
    ) as r:
        text = "".join(r.iter_text())
    if r.status_code == 200:
        import pytest

        with pytest.raises(AssertionError):
            parse_genkit_sse(text)
    else:
        assert r.status_code in (400, 422)
