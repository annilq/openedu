"""``POST /tasks/{task_id}/regenerate-stream`` 回归测试。

覆盖两条路径：
  1) 正常：SSE 帧序 RUN_STARTED → STEP → 逐题 STEP → DATA(task) → DONE，且整卷已落库；
  2) 无可用 LLM 引擎：流内回 ERROR 帧（流已开，不能再改 HTTP 状态码），不抛 500。

存在理由：同步版 ``/regenerate`` 要把整卷 N 道题一次性出完才返回（实测 2 题 19–36 秒），
远超前端普通请求的 30 秒 receiveTimeout——卷子越大必挂。流式版是这个体验问题的修复
手段，本测试守住「帧协议 + 逐题进度 + 落库 + 错误帧」四件事，防止重构时悄悄退化。
"""
from __future__ import annotations

import json
import uuid

from sqlmodel import Session as DBSession

from app.core.db import engine
from app.db.models import Task, TaskQuestion
from app.domain.provider import GeneratedQuestion, QuestionCard, ReasoningDelta
from app.features.tasks import service as tasks_service
from tests.utils.user import auth_headers, register_parent


def _parent_id(client, token: str) -> uuid.UUID:
    r = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return uuid.UUID(r.json()["id"])


def _make_draft(pid: uuid.UUID, n: int = 1, count: int = 2) -> uuid.UUID:
    """建一个带生成规格（count 题）的草稿任务，另附 n 道旧题。"""
    with DBSession(engine) as s:
        task = Task(
            title="草稿",
            status="draft",
            parent_id=pid,
            specs=[
                {
                    "subject": "数学",
                    "grade": 2,
                    "knowledge_point": "加法",
                    "qtype": "calc",
                    "difficulty": "easy",
                    "count": count,
                }
            ],
        )
        s.add(task)
        s.commit()
        s.refresh(task)
        for i in range(n):
            s.add(
                TaskQuestion(
                    task_id=task.id,
                    question_id=None,
                    subject="数学",
                    grade=2,
                    knowledge_point="加法",
                    qtype="calc",
                    stem=f"旧题{i}",
                    answer="0",
                    explanation="略",
                    difficulty="easy",
                )
            )
        s.commit()
        return task.id


def _frames(body: str) -> list[dict]:
    """SSE 正文 → 事件 dict 列表（按 ``\\n\\n`` 切帧，取 ``data:`` 行）。"""
    out: list[dict] = []
    for block in body.split("\n\n"):
        for line in block.split("\n"):
            if line.startswith("data:"):
                payload = line[5:].strip()
                if payload:
                    out.append(json.loads(payload))
    return out


def test_stream_regenerate_all_persists_new_questions(client, monkeypatch):
    ptoken = register_parent(client, username="sse_regenall_p1").json()["access_token"]
    pid = _parent_id(client, ptoken)
    task_id = _make_draft(pid, n=3, count=2)

    seen = {"n": 0}

    async def _fake_stream(engine, **kw):
        """模拟出题管线：每题先吐一段推理文本，再给题卡。"""
        seen["n"] += 1
        i = seen["n"]
        yield ReasoningDelta(delta=f"第 {i} 题思路：先定情境，再配干扰项，最后控难度。")
        yield QuestionCard(
            question=GeneratedQuestion(
                subject="数学",
                grade=2,
                knowledge_point="加法",
                qtype="calc",
                stem=f"新题{i}",
                options=None,
                answer="15",
                explanation="进位加法",
                difficulty="easy",
            ),
            reasoning=f"第 {i} 题思路",
        )

    monkeypatch.setattr(tasks_service, "_gen_question_stream", _fake_stream)

    with client.stream(
        "POST",
        f"/api/v1/tasks/{task_id}/regenerate-stream",
        headers=auth_headers(ptoken),
    ) as resp:
        assert resp.status_code == 200, resp.status_code
        body = "".join(resp.iter_text())

    frames = _frames(body)
    types = [f["eventType"] for f in frames]
    assert types[0] == "RUN_STARTED"
    assert types[-1] == "DONE"
    assert types[-2] == "DATA"
    # 逐题进度文案必须带「第 i/N 题」，家长才有反馈（STEP 帧的文案走 label 字段）
    steps = [f["label"] for f in frames if f["eventType"] == "STEP"]
    assert any("第 1/2 题" in m for m in steps)
    assert any("第 2/2 题" in m for m in steps)
    # 每题一段实时文本：两题各有一个 THINKING 帧（攒批后），不能只跳进度
    thinkings = [f.get("text") or "" for f in frames if f["eventType"] == "THINKING"]
    assert len(thinkings) == 2, thinkings
    assert "第 1 题思路" in thinkings[0]
    assert "第 2 题思路" in thinkings[1]

    data = frames[-2]["data"]
    assert data["type"] == "task"
    assert [q["stem"] for q in data["result"]["questions"]] == ["新题1", "新题2"]

    # 落库生效（流式版与同步版共用同一条写路径）
    r = client.get(f"/api/v1/tasks/{task_id}", headers=auth_headers(ptoken))
    assert r.status_code == 200
    assert [q["stem"] for q in r.json()["questions"]] == ["新题1", "新题2"]


def test_stream_regenerate_all_reports_error_in_stream(client):
    """无 LLM 引擎：同步版 500，流式版必须在流内以 ERROR 帧收尾。"""
    ptoken = register_parent(client, username="sse_regenall_p2").json()["access_token"]
    pid = _parent_id(client, ptoken)
    task_id = _make_draft(pid, n=1, count=1)

    with client.stream(
        "POST",
        f"/api/v1/tasks/{task_id}/regenerate-stream",
        headers=auth_headers(ptoken),
    ) as resp:
        assert resp.status_code == 200, resp.status_code
        body = "".join(resp.iter_text())

    frames = _frames(body)
    types = [f["eventType"] for f in frames]
    assert types == ["RUN_STARTED", "STEP", "STEP", "ERROR", "DONE"]
    err = frames[3]
    assert err["code"] == "SYS_10006"
    assert "LLM" in err["message"]


def test_stream_regenerate_all_rejects_empty_specs(client):
    """specs 为空（题库组卷的草稿）：流内回 ERROR，不让家长干等。"""
    ptoken = register_parent(client, username="sse_regenall_p3").json()["access_token"]
    pid = _parent_id(client, ptoken)
    with DBSession(engine) as s:
        task = Task(title="题库组卷草稿", status="draft", parent_id=pid, specs=[])
        s.add(task)
        s.commit()
        s.refresh(task)
        task_id = task.id

    with client.stream(
        "POST",
        f"/api/v1/tasks/{task_id}/regenerate-stream",
        headers=auth_headers(ptoken),
    ) as resp:
        assert resp.status_code == 200, resp.status_code
        body = "".join(resp.iter_text())

    frames = _frames(body)
    types = [f["eventType"] for f in frames]
    # 前置校验在开流之前就失败 → 只有 ERROR + DONE（没有 RUN_STARTED）
    assert types == ["ERROR", "DONE"]
    assert "生成规格" in frames[0]["message"]
