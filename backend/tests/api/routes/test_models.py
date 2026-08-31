"""模型管理接口测试（ADR-0015 / 票据 08）：CRUD + api_key 加密 + 越权 403/404。"""
from __future__ import annotations

import uuid

from sqlmodel import Session

from app.core.crypto import decrypt
from app.models import ModelConfig
from tests.utils.user import auth_headers, login, register_parent


def _parent(client, suffix="p1"):
    register_parent(client, username=f"parent_{suffix}", password="pw123456")
    token = login(client, f"parent_{suffix}", "pw123456").json()["access_token"]
    return auth_headers(token)


def test_list_models_empty(client):
    h = _parent(client, "list")
    r = client.get("/api/v1/models", headers=h)
    assert r.status_code == 200
    body = r.json()
    assert body["builtin"] == []  # 默认无内置模型
    assert body["custom"] == []


def test_create_and_encryption(client, db: Session):
    h = _parent(client, "enc")
    payload = {
        "label": "我家 Ollama",
        "provider": "ollama",
        "base_url": "http://localhost:11434",
        "model_name": "llama3",
        "api_key": "topsecret",
        "is_default": True,
    }
    r = client.post("/api/v1/models", headers=h, json=payload)
    assert r.status_code == 201
    mid = r.json()["id"]
    # 响应不含 api_key 明文
    assert "api_key" not in r.json()

    # 落库加密：明文不应直接出现在库
    mc = db.get(ModelConfig, uuid.UUID(mid))
    assert mc is not None
    assert mc.api_key_enc != "topsecret"
    assert decrypt(mc.api_key_enc) == "topsecret"
    # 默认模型
    assert mc.is_default is True


def test_update_and_default(client, db: Session):
    h = _parent(client, "upd")
    created = client.post(
        "/api/v1/models",
        headers=h,
        json={"label": "M", "provider": "ollama", "model_name": "llama3"},
    ).json()
    mid = created["id"]
    # 设默认
    r = client.put("/api/v1/models/default", headers=h, json={"id": mid})
    assert r.status_code == 200
    assert r.json()["is_default"] is True
    # 改 label
    r2 = client.put(f"/api/v1/models/{mid}", headers=h, json={"label": "M2"})
    assert r2.status_code == 200
    assert r2.json()["label"] == "M2"


def test_cross_parent_forbidden(client, db: Session):
    h1 = _parent(client, "owner")
    h2 = _parent(client, "other")
    mid = client.post(
        "/api/v1/models",
        headers=h1,
        json={"label": "M", "provider": "ollama", "model_name": "llama3"},
    ).json()["id"]
    # 另一家长访问 → 404（不属于自己）
    assert client.get(f"/api/v1/models/{mid}", headers=h2).status_code in (403, 404)
    assert client.put(f"/api/v1/models/{mid}", headers=h2, json={"label": "x"}).status_code in (403, 404)
    assert client.delete(f"/api/v1/models/{mid}", headers=h2).status_code in (403, 404)


def test_delete(client, db: Session):
    h = _parent(client, "del")
    mid = client.post(
        "/api/v1/models",
        headers=h,
        json={"label": "M", "provider": "ollama", "model_name": "llama3"},
    ).json()["id"]
    assert client.delete(f"/api/v1/models/{mid}", headers=h).status_code == 204
    assert db.get(ModelConfig, uuid.UUID(mid)) is None
