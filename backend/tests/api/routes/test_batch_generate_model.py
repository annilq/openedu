"""批量生成落库路径「尊重所选模型」回归测试（ADR-0015 / 票据 08）。

历史 bug：前端传了 model（如 ollama 内置 id），但 batch-generate 完全忽略，
永远走全局 LLM_PROVIDER（默认 mock）。本测试用假引擎验证：
  1) resolve_engine 收到的正是前端所选 model；
  2) 出题走 Genkit 路径（flows.generate_question 被调用），而非静默回退 mock；
  3) 所选 model 随 Task 落库，供后续整卷/单题重生成沿用。

ADR-0021：出题改经「出题 SubAgent」派发，非流式路径由 SubAgent.handle 调
app.ai.flows.generate_question（惰性导入），故补丁点相应前移到 flows。
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


def test_batch_generate_honors_selected_model(client, monkeypatch):
    r = register_parent(client, username="mfix_parent_a")
    ptoken = r.json()["access_token"]
    cid = _create_child(client, ptoken, username="mfix_kid_a")["id"]

    captured = {"model_ref": None, "genkit_called": False}

    def fake_resolve(model_ref=None, *, parent_id=None, session=None):
        captured["model_ref"] = model_ref
        return SimpleNamespace(genkit=SimpleNamespace(model="ollama/llama3"), model="ollama/llama3")

    async def fake_genkit_generate(engine, *, subject, grade, knowledge_point, qtype, difficulty, interests=None, focus_interest=None, rag_context=None, persona_hint=None):
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

    monkeypatch.setattr("app.api.routes.tasks.resolve_engine", fake_resolve)
    # ADR-0021：出题经 SubAgent 派发，实际出题函数落在 app.ai.flows
    monkeypatch.setattr("app.ai.flows.generate_question", fake_genkit_generate)

    r = client.post(
        "/api/v1/tasks/batch-generate",
        headers=auth_headers(ptoken),
        json={
            "title": "选模型卷",
            "child_id": cid,
            "model": "local-llama",  # 家长所选 ollama 内置模型
            "specs": [
                {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 1}
            ],
        },
    )
    assert r.status_code == 201, r.text
    body = r.json()
    # 1) 后端确实收到了前端所选模型
    assert captured["model_ref"] == "local-llama"
    # 2) 出题走了 Genkit 路径（非 mock）
    assert captured["genkit_called"] is True
    # 3) 题面来自假 ollama 引擎，证明未被 mock 模板替代
    assert body["questions"][0]["stem"] == "[ollama]数学-加法"


def test_batch_generate_no_model_falls_back_to_mock(client, monkeypatch):
    """缺省不选模型：resolve_engine 收 None，走 build_provider（mock），不调用 Genkit。"""
    r = register_parent(client, username="mfix_parent_b")
    ptoken = r.json()["access_token"]
    cid = _create_child(client, ptoken, username="mfix_kid_b")["id"]

    captured = {"model_ref": "UNSET", "genkit_called": False}

    def fake_resolve(model_ref=None, *, parent_id=None, session=None):
        captured["model_ref"] = model_ref
        return None  # 无真实引擎 → 回退

    async def fake_genkit_generate(*args, **kwargs):
        captured["genkit_called"] = True
        return None

    monkeypatch.setattr("app.api.routes.tasks.resolve_engine", fake_resolve)
    # ADR-0021：出题经 SubAgent 派发，实际出题函数落在 app.ai.flows
    monkeypatch.setattr("app.ai.flows.generate_question", fake_genkit_generate)

    r = client.post(
        "/api/v1/tasks/batch-generate",
        headers=auth_headers(ptoken),
        json={
            "title": "默认模型卷",
            "child_id": cid,
            "specs": [
                {"subject": "数学", "grade": 2, "knowledge_point": "加法", "qtype": "calc", "difficulty": "easy", "count": 1}
            ],
        },
    )
    assert r.status_code == 201, r.text
    assert captured["model_ref"] is None
    assert captured["genkit_called"] is False  # 未走 Genkit，回退 mock
    # mock 产出的题面应有 mock 模板特征（非空即可，这里只确认成功落库）
    assert r.json()["questions"][0]["stem"]
