"""``POST /tasks/{task_id}/questions/{tq_id}/regenerate-stream`` 回归测试。

覆盖两条路径：
  1) 正常：SSE 帧序 RUN_STARTED → STEP → **THINKING（模型实时文本）** → DATA(question)
     → DONE，且新题已落库；
  2) 无可用 LLM 引擎：流内回 ERROR 帧（流已开，不能再改 HTTP 状态码），不抛 500。

存在理由：同步版 ``/regenerate`` 是一次同步 LLM 调用，实测超过前端普通请求的 30 秒
receiveTimeout，家长点「换一题」会长时间无反馈甚至超时；流式版是这个体验问题的
修复手段，本测试守住「帧协议 + 落库 + 错误帧」三件事，防止重构时悄悄退化。

THINKING 帧是「点了会转进度但看不到模型在写什么」这个 bug 的回归防线：出题管线
本来就逐段产出 ReasoningDelta，此前被同步 drain 版吞掉，这里断言它必须下发到前端。
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


def _make_draft(pid: uuid.UUID, n: int = 2) -> tuple[uuid.UUID, list[uuid.UUID]]:
    with DBSession(engine) as s:
        task = Task(title="草稿", status="draft", parent_id=pid)
        s.add(task)
        s.commit()
        s.refresh(task)
        tq_ids = []
        for i in range(n):
            tq = TaskQuestion(
                task_id=task.id,
                question_id=None,
                subject="数学",
                grade=2,
                knowledge_point="加法",
                qtype="calc",
                stem=f"{i}+{i}=?",
                answer=str(i * 2),
                explanation="略",
                difficulty="easy",
            )
            s.add(tq)
            s.commit()
            s.refresh(tq)
            tq_ids.append(tq.id)
        return task.id, tq_ids


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


def test_stream_regenerate_persists_new_question(client, monkeypatch):
    ptoken = register_parent(client, username="sse_regen_p1").json()["access_token"]
    pid = _parent_id(client, ptoken)
    task_id, tq_ids = _make_draft(pid, n=2)

    async def _fake_stream(engine, **kw):
        """模拟出题管线的语义事件流：先逐段推理文本，再给题卡。"""
        yield ReasoningDelta(delta="先确定情境：用分糖果讲进位加法，")
        yield ReasoningDelta(delta="再设计干扰项，最后把控难度。")
        yield QuestionCard(
            question=GeneratedQuestion(
                subject="数学",
                grade=2,
                knowledge_point="加法",
                qtype="calc",
                stem="7+8=?",
                options=None,
                answer="15",
                explanation="进位加法",
                difficulty="easy",
            ),
            reasoning="先确定情境：用分糖果讲进位加法，再设计干扰项，最后把控难度。",
        )

    monkeypatch.setattr(tasks_service, "_gen_question_stream", _fake_stream)

    with client.stream(
        "POST",
        f"/api/v1/tasks/{task_id}/questions/{tq_ids[0]}/regenerate-stream",
        headers=auth_headers(ptoken),
    ) as resp:
        assert resp.status_code == 200, resp.status_code
        body = "".join(resp.iter_text())

    frames = _frames(body)
    types = [f["eventType"] for f in frames]
    # THINKING 必须有：模型实时文本此前被同步 drain 版吞掉，家长只能看进度跳变。
    assert "THINKING" in types, types
    assert types[0] == "RUN_STARTED"
    assert types[-1] == "DONE"
    assert types[-2] == "DATA"

    thinking = "".join(f.get("text") or "" for f in frames
                       if f["eventType"] == "THINKING")
    assert "分糖果" in thinking

    data = frames[-2]["data"]
    assert data["type"] == "question"
    assert data["result"]["stem"] == "7+8=?"
    assert data["result"]["id"] == str(tq_ids[0])  # 原地覆盖，不是新建草稿项

    # 落库生效（流式版与同步版共用同一条写路径）
    r = client.get(f"/api/v1/tasks/{task_id}", headers=auth_headers(ptoken))
    assert r.status_code == 200
    assert "7+8=?" in [q["stem"] for q in r.json()["questions"]]


def test_stream_regenerate_reports_error_in_stream(client):
    """无可用 AI 出题引擎：同步版 500，流式版必须在流内以 ERROR 帧收尾。"""
    ptoken = register_parent(client, username="sse_regen_p2").json()["access_token"]
    pid = _parent_id(client, ptoken)
    task_id, tq_ids = _make_draft(pid, n=1)

    with client.stream(
        "POST",
        f"/api/v1/tasks/{task_id}/questions/{tq_ids[0]}/regenerate-stream",
        headers=auth_headers(ptoken),
    ) as resp:
        assert resp.status_code == 200, resp.status_code
        body = "".join(resp.iter_text())

    frames = _frames(body)
    types = [f["eventType"] for f in frames]
    assert types == ["RUN_STARTED", "STEP", "ERROR", "DONE"]
    err = frames[2]
    assert err["code"] == "SYS_10006"
    assert "出题引擎" in err["message"]
