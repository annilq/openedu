"""POST /api/v1/tasks/generate 结构化出题端点测试（ADR-0034 Phase 1）。

回归核心：多行 specs（各 1 道）必须产出与总行数对应的题卡数，而不是被「自由文本 →
正则解析」吞成 1 道（即先前「总题数 2 只出 1 题」的根因）。结构化规格直传后端，服务端
构造 prompt 后走 question subagent 流式返回 DATA 题卡。
"""
from __future__ import annotations

import json
import uuid

import pytest

from tests.utils.fake_provider import FakeLLMProvider
from tests.utils.user import auth_headers, register_parent


def _count_question_cards(sse_text: str) -> int:
    """统计 SSE 流中 DATA(type=question) 帧数（= 生成的题卡数）。"""
    cards = 0
    for raw in sse_text.split("\n\n"):
        frame = raw.strip()
        if not frame.startswith("data:"):
            continue
        payload = frame[len("data:") :].strip()
        if not payload:
            continue
        try:
            obj = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if obj.get("eventType") == "DATA" and (obj.get("data") or {}).get("type") == "question":
            cards += 1
    return cards


def _patch_provider(monkeypatch) -> None:
    """本端点经归一封装 build_ai_provider 构造 provider（ADR-0034 Phase 2）；
    autouse 的 fake_llm 只覆盖 assistant.router，故须就地打桩。"""
    monkeypatch.setattr(
        "app.features.tasks.router.build_ai_provider",
        lambda model_ref=None, *, parent_id=None, session=None: FakeLLMProvider(),
    )


@pytest.fixture
def parent_token(client):
    # 唯一用户名，避免 session 级 db 夹具下「用户名已注册」冲突（用户跨测试累积）。
    username = f"parent_{uuid.uuid4().hex[:8]}"
    r = register_parent(client, username=username)
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def test_generate_multi_row_specs_produces_total_cards(client, parent_token, monkeypatch):
    """多行 specs（数学 1 + 语文 1）应产出 2 张题卡，而非被正则吞成 1 张。"""
    _patch_provider(monkeypatch)
    body = {
        "specs": [
            {
                "subject": "数学",
                "grade": 3,
                "knowledge_point": "两位数加减法",
                "qtype": "calc",
                "count": 1,
            },
            {
                "subject": "语文",
                "grade": 3,
                "knowledge_point": "字词积累",
                "qtype": "fill",
                "count": 1,
            },
        ],
    }
    r = client.post("/api/v1/tasks/generate", headers=auth_headers(parent_token), json=body)
    assert r.status_code == 200, r.text
    assert _count_question_cards(r.text) == 2


def test_generate_single_row_count_two_produces_two_cards(client, parent_token, monkeypatch):
    """单行 count=2 应产出 2 张（原链路在本场景已正确，作对照守护）。"""
    _patch_provider(monkeypatch)
    body = {
        "specs": [
            {
                "subject": "数学",
                "grade": 3,
                "knowledge_point": "分数",
                "qtype": "choice",
                "count": 2,
            },
        ],
    }
    r = client.post("/api/v1/tasks/generate", headers=auth_headers(parent_token), json=body)
    assert r.status_code == 200, r.text
    assert _count_question_cards(r.text) == 2


def test_generate_three_rows_mixed_counts(client, parent_token, monkeypatch):
    """多行混合题量（2+1+3）应产出 6 张，验证结构化规格总数不再丢失。"""
    _patch_provider(monkeypatch)
    body = {
        "specs": [
            {"subject": "数学", "grade": 3, "knowledge_point": "计算", "qtype": "calc", "count": 2},
            {"subject": "语文", "grade": 3, "knowledge_point": "字词", "qtype": "fill", "count": 1},
            {"subject": "英语", "grade": 3, "knowledge_point": "词汇", "qtype": "choice", "count": 3},
        ],
    }
    r = client.post("/api/v1/tasks/generate", headers=auth_headers(parent_token), json=body)
    assert r.status_code == 200, r.text
    assert _count_question_cards(r.text) == 6


def test_generate_empty_specs_rejected(client, parent_token, monkeypatch):
    """空 specs 必须被显式拒绝（422），不得静默少出。"""
    _patch_provider(monkeypatch)
    r = client.post(
        "/api/v1/tasks/generate",
        headers=auth_headers(parent_token),
        json={"specs": []},
    )
    assert r.status_code == 422
