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
from tests.utils.user import auth_headers, register_teacher


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


def _patch_provider(monkeypatch, *, fail_at: set[int] | None = None) -> None:
    """本端点经归一封装 build_ai_provider 构造 provider（ADR-0034 Phase 2）；
    autouse 的 fake_llm 只覆盖 assistant.router，故须就地打桩。

    打桩点是 **service**（ADR-0033 把编排从 router 下沉到 service 后，router 已不再
    import build_ai_provider——此前打在 router 上会让本文件 4 个用例全部以
    AttributeError 崩溃，等于这条「多学科出题」回归防线长期失效）。
    ``fail_at`` 指定第几次模型调用失败，用于验证部分失败时少题是否如实上报。

    ADR-0097 起出题是 tool loop：替身须脚本化首轮选中 ``generate_questions``
    （规格由端点的 specs 经 ctx.extra 直达 handler，空 args 即按系统规格出题）；
    不脚本化的默认单跳会命中工具列表第一个（list_bank_questions）而出不了题。
    """
    monkeypatch.setattr(
        "app.features.tasks.service.build_ai_provider",
        lambda model_ref=None, *, teacher_id=None, session=None: FakeLLMProvider(
            fail_at=fail_at or set()
        ).script("generate_questions"),
    )


@pytest.fixture
def teacher_token(client):
    # 唯一用户名，避免 session 级 db 夹具下「用户名已注册」冲突（用户跨测试累积）。
    username = f"teacher_{uuid.uuid4().hex[:8]}"
    r = register_teacher(client, username=username)
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def test_generate_multi_row_specs_produces_total_cards(client, teacher_token, monkeypatch):
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
    r = client.post("/api/v1/tasks/generate", headers=auth_headers(teacher_token), json=body)
    assert r.status_code == 200, r.text
    assert _count_question_cards(r.text) == 2


def test_generate_single_row_count_two_produces_two_cards(client, teacher_token, monkeypatch):
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
    r = client.post("/api/v1/tasks/generate", headers=auth_headers(teacher_token), json=body)
    assert r.status_code == 200, r.text
    assert _count_question_cards(r.text) == 2


def test_generate_three_rows_mixed_counts(client, teacher_token, monkeypatch):
    """多行混合题量（2+1+3）应产出 6 张，验证结构化规格总数不再丢失。"""
    _patch_provider(monkeypatch)
    body = {
        "specs": [
            {"subject": "数学", "grade": 3, "knowledge_point": "计算", "qtype": "calc", "count": 2},
            {"subject": "语文", "grade": 3, "knowledge_point": "字词", "qtype": "fill", "count": 1},
            {"subject": "英语", "grade": 3, "knowledge_point": "词汇", "qtype": "choice", "count": 3},
        ],
    }
    r = client.post("/api/v1/tasks/generate", headers=auth_headers(teacher_token), json=body)
    assert r.status_code == 200, r.text
    assert _count_question_cards(r.text) == 6


def test_generate_empty_specs_rejected(client, teacher_token, monkeypatch):
    """空 specs 必须被显式拒绝（422），不得静默少出。"""
    _patch_provider(monkeypatch)
    r = client.post(
        "/api/v1/tasks/generate",
        headers=auth_headers(teacher_token),
        json={"specs": []},
    )
    assert r.status_code == 422


def _parse_frames(sse_text: str) -> list[dict]:
    """解析 SSE 文本为帧列表（与端点序列化形状一致）。"""
    out: list[dict] = []
    for raw in sse_text.split("\n\n"):
        frame = raw.strip()
        if not frame.startswith("data:"):
            continue
        try:
            out.append(json.loads(frame[len("data:") :].strip()))
        except json.JSONDecodeError:
            continue
    return out


def test_generate_partial_failure_reports_shortfall(client, teacher_token, monkeypatch):
    """数学+语文各 1 题、语文那次失败：必须只出 1 张卡，且失败在流里留痕。

    这是本次缺陷的端点级回归：失败题此前只产出一条 STEP(status=error)，前端当普通
    进度吞掉后照常落库 → 教师拿到「只有数学」的草稿却毫无提示。

    ADR-0097 起出题是流式 tool，失败痕迹有两处**确定性**证据（收尾话术由模型据
    回灌计数生成，属真机形态，替身只发固定文本、不断言其内容）：
    ① 失败题产出 STEP(status="error") 帧（translate_stream 的转换）；
    ② 回灌的 ToolOutcome 带 requested=2 / count=1 / failed=1（TOOL_RESULT 载荷，
    收尾轮的数据源）。
    """
    _patch_provider(monkeypatch, fail_at={2})
    body = {
        "specs": [
            {"subject": "数学", "grade": 3, "knowledge_point": "计算", "qtype": "calc", "count": 1},
            {"subject": "语文", "grade": 3, "knowledge_point": "字词", "qtype": "fill", "count": 1},
        ],
    }
    r = client.post("/api/v1/tasks/generate", headers=auth_headers(teacher_token), json=body)
    assert r.status_code == 200, r.text
    assert _count_question_cards(r.text) == 1

    frames = _parse_frames(r.text)
    # ① 失败题的状态帧：status=error（前端据此提示，而不是当普通进度吞掉）
    error_steps = [
        f for f in frames
        if f.get("eventType") == "STEP" and f.get("status") == "error"
    ]
    assert error_steps, "失败题必须留痕（STEP status=error）"
    # ② 回灌计数：应出 2 / 实出 1 / 失败 1
    tool_results = [f for f in frames if f.get("eventType") == "TOOL_RESULT"]
    assert tool_results, "流式 tool 必须补 TOOL_RESULT 关闭调用配对"
    payload = tool_results[-1].get("result") or {}
    assert payload.get("requested") == 2
    assert payload.get("count") == 1
    assert payload.get("failed") == 1
