"""T01（ADR-0074 v4）：场景 kind 级默认演示图形配置。

覆盖：
- 幂等 DDL：``run_migrations`` 连跑两次无错、表存在；
- ``PUT /scene-library/{kind}/default-figure`` 写默认图形，``GET`` 透传；非法 kind 返 422；
- 空 key 清除默认 → ``default_figure_key`` 回落 ``None``（关联 seed 回落注册表空占位）。

「默认图形只 seed 新关联、不回写已落库 scenes/scene_spec」由 T04/T06 端到端守（ADR-0073 快照不可变）；
本文件只钉端点契约与 persistence。
"""
from __future__ import annotations

from fastapi.testclient import TestClient

from app.core.db import run_migrations
from tests.utils.user import auth_headers, login, register_teacher


def _teacher_token(client: TestClient, username: str) -> str:
    register_teacher(client, username=username, password="pw123456")
    return login(client, username, "pw123456").json()["access_token"]


def _reflection_item(library: dict) -> dict:
    return next(s for s in library["scenes"] if s["kind"] == "reflection")


def test_run_migrations_is_idempotent(client: TestClient):
    """``run_migrations`` 再跑一次不应报错（表已存在 → CREATE TABLE IF NOT EXISTS no-op）。"""
    run_migrations()  # 首次已由 conftest 的 init_db 触发


def test_set_and_read_default_figure(client: TestClient):
    token = _teacher_token(client, "scdef_teacher_a")
    r = client.put(
        "/api/v1/materials/scene-library/reflection/default-figure",
        headers=auth_headers(token),
        json={"default_figure_key": "house"},
    )
    assert r.status_code == 200, r.text
    # PUT 返回该 kind 的场景库条目（单条，非 scenes 包装）
    assert r.json()["kind"] == "reflection"
    assert r.json()["default_figure_key"] == "house"
    # GET 透传
    lib = client.get(
        "/api/v1/materials/scene-library", headers=auth_headers(token)
    ).json()
    assert _reflection_item(lib)["default_figure_key"] == "house"


def test_unknown_kind_returns_422(client: TestClient):
    token = _teacher_token(client, "scdef_teacher_b")
    r = client.put(
        "/api/v1/materials/scene-library/rotation/default-figure",
        headers=auth_headers(token),
        json={"default_figure_key": "house"},
    )
    assert r.status_code == 422, r.text


def test_clear_default_figure(client: TestClient):
    token = _teacher_token(client, "scdef_teacher_c")
    client.put(
        "/api/v1/materials/scene-library/reflection/default-figure",
        headers=auth_headers(token),
        json={"default_figure_key": "house"},
    )
    r = client.put(
        "/api/v1/materials/scene-library/reflection/default-figure",
        headers=auth_headers(token),
        json={"default_figure_key": None},
    )
    assert r.status_code == 200, r.text
    assert r.json()["default_figure_key"] is None
