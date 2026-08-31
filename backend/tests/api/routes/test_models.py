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


def test_list_provider_presets(client):
    h = _parent(client, "prov")
    r = client.get("/api/v1/models/providers", headers=h)
    assert r.status_code == 200
    body = r.json()
    assert isinstance(body, list) and len(body) >= 2
    keys = {p["key"] for p in body}
    assert "deepseek" in keys and "openai" in keys
    # 每个预设都带默认 base_url 与模型名建议
    ds = next(p for p in body if p["key"] == "deepseek")
    assert ds["base_url"] == "https://api.deepseek.com"
    assert "deepseek-v4-flash" in ds["models"]


def test_create_with_provider_preset(client, db: Session):
    h = _parent(client, "preset")
    # 只选服务商预设 + 模型名 + key，不手写 provider/base_url
    r = client.post(
        "/api/v1/models",
        headers=h,
        json={
            "label": "我的 DeepSeek",
            "provider_preset": "deepseek",
            "model_name": "deepseek-v4-flash",
            "api_key": "sk-test",
            "is_default": True,
        },
    )
    assert r.status_code == 201, r.text
    body = r.json()
    # 自动补全 provider 与 base_url
    assert body["provider"] == "openai_compat"
    assert body["base_url"] == "https://api.deepseek.com"
    assert body["model_name"] == "deepseek-v4-flash"
    assert body["is_default"] is True
    # 落库校验
    mc = db.get(ModelConfig, uuid.UUID(body["id"]))
    assert mc is not None
    assert mc.provider == "openai_compat"
    assert mc.base_url == "https://api.deepseek.com"
    assert mc.api_key_enc != "sk-test"


def test_create_with_unknown_preset(client):
    h = _parent(client, "badpreset")
    r = client.post(
        "/api/v1/models",
        headers=h,
        json={
            "label": "X",
            "provider_preset": "no-such-provider",
            "model_name": "gpt-4o",
        },
    )
    assert r.status_code in (400, 422)
    assert "服务商预设" in r.text



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
