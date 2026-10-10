"""``POST /tasks/{task_id}/questions/{tq_id}/regenerate-stream`` 回归测试。

覆盖四条路径：
  1) 正常：换一题走**统一路由**（``rt.decide`` 动作直配 + ``rt.run``），帧序与
     ``/tasks/generate`` 同形（含 USER_MESSAGE / 路由 THINKING / TOOL_CALL /
     TOOL_RESULT 工具信封），题卡落库后再以 DATA(question) 下发（带 id + source_refs）；
  2) 动作直配：``decide`` 收到动作 ``task_question_regenerate``、``run`` 走 ``question``；
  3) 无可用 LLM 引擎：流内不产题卡（STEP(status=error) + 收尾），以 DONE 结束，不抛 500；
  4) 传他人任务 id：ERROR 帧报「任务不存在」（归属校验语义不变，不暴露任务存在性）。

存在理由：换一题此前直连裸出题管线、绕过运行时，资料库检索 / 学科提示 / 溯源引用 /
工具信封**一项都没有**——教师感觉「换出来的题比第一次差」。本测试守住「帧协议 +
能力集（溯源 / 工具信封）+ 落库 + 归属」四件事，防止重构时悄悄退回裸管线。
"""
from __future__ import annotations

import json
import uuid

from sqlmodel import Session as DBSession

from agent_core.ports import LLMProvider, StructuredDone, TextDelta
from agent_core.protocol import data_event, done, thinking, tool_call
from agent_core.runtime import RouteDecision
from app.core.db import engine
from app.db.models import Task, TaskQuestion
from app.domain.retriever import KnowledgeChunk
from app.features.tasks import service as tasks_service
from tests.utils.user import auth_headers, register_teacher


def _teacher_id(client, token: str) -> uuid.UUID:
    r = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return uuid.UUID(r.json()["id"])


def _make_draft(pid: uuid.UUID, n: int = 2) -> tuple[uuid.UUID, list[uuid.UUID]]:
    with DBSession(engine) as s:
        task = Task(title="草稿", status="draft", teacher_id=pid)
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


class _FakeQuestionProvider(LLMProvider):
    """假出题引擎：先吐推理文本，再给结构化题卡（与真实 provider 契约一致）。"""

    configured = True

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        yield TextDelta(delta="先确定情境：用分糖果讲进位加法，")
        yield TextDelta(delta="再设计干扰项。")
        yield StructuredDone(
            data={
                "subject": "数学",
                "grade": 2,
                "knowledge_point": "加法",
                "qtype": "calc",
                "stem": "7+8=?",
                "options": None,
                "answer": "15",
                "explanation": "进位加法",
                "difficulty": "easy",
                "reasoning": "先确定情境，再设计干扰项。",
            }
        )


class _StubRetriever:
    """命中一份教师私有资料，验证换一题真的接了资料库检索、溯源随题下发。"""

    def retrieve(self, *, subject, grade, knowledge_point, query):
        return [
            KnowledgeChunk(
                subject=subject,
                grade=grade,
                knowledge_point=knowledge_point,
                content="进位加法：个位相加满十向前一位进一。",
                source="vector",
                source_name="资料A.md",
            )
        ]


def _stub_deps(monkeypatch) -> None:
    monkeypatch.setattr(
        tasks_service,
        "build_ai_provider",
        lambda model_ref=None, *, teacher_id=None, session=None: _FakeQuestionProvider(),
    )
    monkeypatch.setattr(
        tasks_service,
        "build_retriever",
        lambda session=None, teacher_id=None: _StubRetriever(),
    )


def test_stream_regenerate_routes_via_runtime_and_persists(client, monkeypatch):
    ptoken = register_teacher(client, username="sse_regen_p1").json()["access_token"]
    pid = _teacher_id(client, ptoken)
    task_id, tq_ids = _make_draft(pid, n=2)
    _stub_deps(monkeypatch)

    with client.stream(
        "POST",
        f"/api/v1/tasks/{task_id}/questions/{tq_ids[0]}/regenerate-stream",
        headers=auth_headers(ptoken),
    ) as resp:
        assert resp.status_code == 200, resp.status_code
        body = "".join(resp.iter_text())

    frames = _frames(body)
    types = [f["eventType"] for f in frames]
    # 运行时帧：工具信封（TOOL_CALL / TOOL_RESULT）是「与首次出题同源」的直接证据。
    assert types[0] == "RUN_STARTED", types
    assert "TOOL_CALL" in types, types
    assert "TOOL_RESULT" in types, types
    assert "THINKING" in types, types
    assert types[-1] == "DONE", types
    assert types[-2] == "DATA", types

    # THINKING 必须有：模型实时出题思路逐帧下发（此前被同步 drain 版吞掉）。
    thinking_text = "".join(
        f.get("text") or "" for f in frames if f["eventType"] == "THINKING"
    )
    assert "分糖果" in thinking_text

    # 题卡落库后才下发（带 id），且溯源引用随题下发（资料库检索真生效）。
    data = frames[-2]["data"]
    assert data["type"] == "question"
    assert data["result"]["stem"] == "7+8=?"
    assert data["result"]["id"] == str(tq_ids[0])  # 原地覆盖，不是新建草稿项
    refs = data["result"].get("source_refs")
    assert refs and refs[0]["material"] == "资料A.md", data["result"]

    # 落库生效（流式版与同步版共用同一条写路径）
    r = client.get(f"/api/v1/tasks/{task_id}", headers=auth_headers(ptoken))
    assert r.status_code == 200
    assert "7+8=?" in [q["stem"] for q in r.json()["questions"]]


class _StubRuntime:
    """stub 掉 get_runtime：直接断言「换一题走了统一路由（动作直配 → question）」。"""

    def __init__(self) -> None:
        self.decisions: list[tuple[str | None, str]] = []
        self.businesses: list[str | None] = []

    async def decide(self, signal, *, role, deps):
        self.decisions.append((signal.action, role))
        return RouteDecision(
            business="question", name="出题助手", extra={"routed_by": "action"}
        )

    async def run(self, message, *, role, ctx, deps, business=None, session=None):
        self.businesses.append(business)
        yield tool_call("generate_question", label="出题", args={})
        yield thinking("先定情境……")
        yield data_event(
            {
                "subject": "数学",
                "grade": 2,
                "knowledge_point": "加法",
                "qtype": "calc",
                "stem": "9+9=?",
                "options": None,
                "answer": "18",
                "explanation": "进位",
                "difficulty": "easy",
                "source_refs": [{"material": "资料A.md", "snippet": "满十进一"}],
            },
            extra={"type": "question"},
        )
        yield done()


def test_stream_regenerate_uses_unified_router_action(client, monkeypatch):
    ptoken = register_teacher(client, username="sse_regen_rt").json()["access_token"]
    pid = _teacher_id(client, ptoken)
    task_id, tq_ids = _make_draft(pid, n=1)

    stub = _StubRuntime()
    monkeypatch.setattr(tasks_service, "get_runtime", lambda: stub)

    with client.stream(
        "POST",
        f"/api/v1/tasks/{task_id}/questions/{tq_ids[0]}/regenerate-stream",
        headers=auth_headers(ptoken),
    ) as resp:
        assert resp.status_code == 200, resp.status_code
        body = "".join(resp.iter_text())

    # 动作直配：decide 收到换一题动作，run 走 question 业务。
    assert stub.decisions == [("task_question_regenerate", "teacher")]
    assert stub.businesses == ["question"]

    frames = _frames(body)
    types = [f["eventType"] for f in frames]
    assert "TOOL_CALL" in types and types[-1] == "DONE"
    data = [f for f in frames if f["eventType"] == "DATA"][-1]["data"]
    assert data["result"]["stem"] == "9+9=?"
    assert data["result"]["id"] == str(tq_ids[0])


def test_stream_regenerate_persists_nothing_without_engine(client):
    """无可用 AI 出题引擎：流内不产题卡、不落库，以 DONE 结束（不抛 500）。"""
    ptoken = register_teacher(client, username="sse_regen_p2").json()["access_token"]
    pid = _teacher_id(client, ptoken)
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
    assert types[0] == "RUN_STARTED"
    assert types[-1] == "DONE"
    # 未生成题卡 → 不发 DATA(question)（不把残缺题落库）。
    assert not any(
        f["eventType"] == "DATA" and (f.get("data") or {}).get("type") == "question"
        for f in frames
    ), types

    # 原题保持不变（没有被残缺内容覆盖）。
    r = client.get(f"/api/v1/tasks/{task_id}", headers=auth_headers(ptoken))
    assert r.status_code == 200
    assert r.json()["questions"][0]["stem"] == "0+0=?"


def test_stream_regenerate_reports_task_not_found_for_other_teacher(client, monkeypatch):
    """传他人任务 id → 报「任务不存在」（归属校验语义不变，不暴露存在性）。"""
    _stub_deps(monkeypatch)
    owner_token = register_teacher(client, username="sse_owner").json()["access_token"]
    other_token = register_teacher(client, username="sse_other").json()["access_token"]
    owner_id = _teacher_id(client, owner_token)
    task_id, tq_ids = _make_draft(owner_id, n=1)

    with client.stream(
        "POST",
        f"/api/v1/tasks/{task_id}/questions/{tq_ids[0]}/regenerate-stream",
        headers=auth_headers(other_token),
    ) as resp:
        assert resp.status_code == 200, resp.status_code
        body = "".join(resp.iter_text())

    frames = _frames(body)
    errs = [f for f in frames if f["eventType"] == "ERROR"]
    assert errs, [f["eventType"] for f in frames]
    assert errs[0]["message"] == "任务不存在"
    assert errs[0]["code"] == "TASK_20001"
    # 越权请求绝不落库
    assert not any(f["eventType"] == "DATA" for f in frames)


def test_regenerate_sync_reports_task_not_found_for_other_teacher(client, monkeypatch):
    """同步换一题端点同样保持「任务不存在」的归属语义（404，而非 403）。"""
    _stub_deps(monkeypatch)
    owner_token = register_teacher(client, username="sync_owner").json()["access_token"]
    other_token = register_teacher(client, username="sync_other").json()["access_token"]
    owner_id = _teacher_id(client, owner_token)
    task_id, tq_ids = _make_draft(owner_id, n=1)

    r = client.post(
        f"/api/v1/tasks/{task_id}/questions/{tq_ids[0]}/regenerate",
        headers=auth_headers(other_token),
    )
    assert r.status_code == 404, r.text
    assert r.json()["code"] == "TASK_20001"
