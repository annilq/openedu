"""出题流式端点真实模型 smoke（票据 08 / ADR-0015）。

默认跳过。仅在本地已起 Ollama（或任意 OpenAI 兼容服务）且显式开启时运行：

    OLLAMA_BASE_URL=http://localhost:11434 \\
    BUILTIN_MODELS='[{"id":"local-llama","label":"Local Llama",
      "provider":"ollama","base_url":"http://localhost:11434",
      "model_name":"qwen2.5:latest"}]' \\
    RUN_LLM_SMOKE=1 \\
        uv run pytest tests/api/routes/test_generate_stream_smoke.py -m smoke -v

验证：经真实引擎（Genkit 编排）的流式出题端点，逐题产出 question 事件并以 done
收尾，题卡字段符合 GeneratedQuestion 契约（subject/stem/answer 等）。
"""
from __future__ import annotations

import json
import os

import pytest

from app.core.config import settings
from tests.utils.sse import parse_sse
from tests.utils.user import auth_headers, login, register_parent

try:
    _models = (
        json.loads(settings.BUILTIN_MODELS) if settings.BUILTIN_MODELS else []
    )
except (json.JSONDecodeError, TypeError):
    _models = []
_ollama_models = [m for m in _models if m.get("provider") == "ollama"]

_smoke_enabled = bool(_ollama_models) and os.environ.get("RUN_LLM_SMOKE") == "1"

pytestmark = [
    pytest.mark.smoke,
    pytest.mark.skipif(
        not _smoke_enabled,
        reason="需 BUILTIN_MODELS 含 provider=ollama 的模型，并设 RUN_LLM_SMOKE=1",
    ),
]


def test_stream_generate_real_ollama(client):
    model = _ollama_models[0]
    register_parent(client, username="smoke_parent", password="pw123456")
    ptoken = login(client, "smoke_parent", "pw123456").json()["access_token"]
    h = auth_headers(ptoken)
    r = client.post(
        "/api/v1/stream/tasks/generate",
        headers=h,
        json={
            "title": "smoke 卷",
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
            "model": model["id"],
        },
    )
    assert r.status_code == 200, r.text
    events = parse_sse(r.text)
    assert events, "未收到任何 SSE 事件"
    questions = [d for e, d in events if e == "question"]
    assert questions, "真实引擎未产出任何题目"
    assert events[-1][0] == "done"
    for q in questions:
        assert q.get("subject") and q.get("stem") and "answer" in q
