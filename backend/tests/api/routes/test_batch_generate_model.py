"""整卷重生成「尊重所选模型」回归测试（ADR-0023：单流收口后，regenerate 复用共享出题核心）。

历史 bug（原 batch-generate）：前端传了 model（如 ollama 内置 id），但旧路径忽略，
永远走全局 LLM_PROVIDER（默认 mock）。batch-generate 已删除，出题统一经
`POST /tasks/from-generated`（落库预设题卡）→ `POST /tasks/{id}/regenerate`
（按 Task.model 复用共享出题管线 ``question.pipeline.generate_question`` 重跑）。本测试用假 provider 验证：
  1) resolve_engine 收到的正是 Task 所选 model；
  2) 重生成走 Genkit 路径（pipeline.generate_question 被调用）；
  3) 所选 model 实际驱动出题（题面来自假 ollama 引擎）。
"""
from __future__ import annotations

from types import SimpleNamespace

from app.domain.provider import GeneratedQuestion
from tests.utils.user import auth_headers, register_parent


def _create_child(client, ptoken, username="kidm1"):
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


def _make_draft(client, ptoken, cid, *, model):
    """单流：先以预设题卡落库 draft（from-generated），再供 regenerate 重跑。"""
    r = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(ptoken),
        json={
            "title": "选模型卷",
            "child_id": cid,
            "model": model,  # 家长所选 ollama 内置模型
            "specs": [
                {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 1}
            ],
            "questions": [
                {
                    "subject": "数学", "grade": 2, "knowledge_point": "加法",
                    "qtype": "calc", "difficulty": "easy",
                    "stem": "占位题", "options": None, "answer": "0",
                    "explanation": "占位",
                }
            ],
        },
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_regenerate_honors_selected_model(client, monkeypatch):
    r = register_parent(client, username="mfix_parent_a")
    ptoken = r.json()["access_token"]
    cid = _create_child(client, ptoken, username="mfix_kid_a")["id"]
    tid = _make_draft(client, ptoken, cid, model="local-llama")

    captured = {"model_ref": None, "genkit_called": False}

    def fake_resolve(model_ref=None, *, parent_id=None, session=None):
        captured["model_ref"] = model_ref
        return SimpleNamespace(genkit=SimpleNamespace(model="ollama/llama3"), model="ollama/llama3")

    async def fake_generate_question(
        provider, *, subject, grade, knowledge_point, qtype, difficulty,
        interests=None, focus_interest=None, rag_context=None, persona_hint=None,
    ):
        captured["genkit_called"] = True
        return GeneratedQuestion(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            qtype=qtype,
            stem=f"[ollama]{subject}-{knowledge_point}",
            options=None,
            answer="42",
            explanation="x",
            difficulty=difficulty,
        )

    monkeypatch.setattr("app.features.tasks.service.resolve_engine", fake_resolve)
    monkeypatch.setattr(
        "app.ai.subagents.question.pipeline.generate_question", fake_generate_question
    )

    r = client.post(f"/api/v1/tasks/{tid}/regenerate", headers=auth_headers(ptoken))
    assert r.status_code == 200, r.text
    body = r.json()
    # 1) 重生成按 Task.model 解析，后端确实收到了所选模型
    assert captured["model_ref"] == "local-llama"
    # 2) 出题走了 Genkit 路径（非 mock）
    assert captured["genkit_called"] is True
    # 3) 题面来自假 ollama 引擎，证明未被 mock 模板替代
    assert body["questions"][0]["stem"] == "[ollama]数学-加法"


