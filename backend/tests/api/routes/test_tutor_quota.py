"""AI 使用管控 API 单测（T10，故事 23/26）。

覆盖：家长设置/查看/清除配置、越权 403、非法配置 422、
学科越界 403、次数上限 429（按娃覆盖全局）、时长上限 429、
用量查询、未配置走全局默认。
"""
from app.core.config import settings
from tests.utils.user import auth_headers, login, register_parent


def _create_child(client, ptoken, username):
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


def _setup(client, parent_u, child_u):
    pr = register_parent(client, username=parent_u)
    assert pr.status_code == 200
    ptoken = pr.json()["access_token"]
    child = _create_child(client, ptoken, child_u)
    lr = login(client, child_u, "kid123456")
    assert lr.status_code == 200
    ctoken = lr.json()["access_token"]
    return ptoken, child, ctoken


def _ask(client, ctoken, subject="数学"):
    return client.post(
        "/api/v1/tutor/ask",
        headers=auth_headers(ctoken),
        json={"subject": subject, "grade": 2, "question": "1+1 等于几"},
    )


def _set_quota(client, ptoken, child_id, body):
    return client.put(
        "/api/v1/tutor/quota",
        headers=auth_headers(ptoken),
        params={"child_id": child_id},
        json=body,
    )


# —— 配置接口 ——
def test_parent_set_and_get_quota(client):
    _ptoken, child, _ctoken = _setup(client, "tq1_parent", "tq1_kid")
    r = _set_quota(
        client,
        _ptoken,
        child["id"],
        {
            "daily_ask_limit": 10,
            "daily_minutes_limit": 20,
            "allowed_subjects": ["数学", "语文"],
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["daily_ask_limit"] == 10
    assert r.json()["allowed_subjects"] == ["数学", "语文"]

    got = client.get(
        "/api/v1/tutor/quota",
        headers=auth_headers(_ptoken),
        params={"child_id": child["id"]},
    )
    assert got.status_code == 200
    assert got.json()["daily_minutes_limit"] == 20


def test_quota_default_when_not_configured(client):
    """未配置：GET 返回全 None 字段（走全局默认）。"""
    _ptoken, child, _ctoken = _setup(client, "tq2_parent", "tq2_kid")
    r = client.get(
        "/api/v1/tutor/quota",
        headers=auth_headers(_ptoken),
        params={"child_id": child["id"]},
    )
    assert r.status_code == 200
    assert r.json()["daily_ask_limit"] is None
    assert r.json()["allowed_subjects"] is None


def test_quota_update_overwrites_and_clears(client):
    """整体覆盖：再设一次以 None 清除时长与范围限制。"""
    _ptoken, child, _ctoken = _setup(client, "tq3_parent", "tq3_kid")
    _set_quota(
        client,
        _ptoken,
        child["id"],
        {"daily_ask_limit": 3, "daily_minutes_limit": 5, "allowed_subjects": ["数学"]},
    )
    r = _set_quota(client, _ptoken, child["id"], {"daily_ask_limit": 8})
    assert r.status_code == 200
    assert r.json()["daily_ask_limit"] == 8
    assert r.json()["daily_minutes_limit"] is None
    assert r.json()["allowed_subjects"] is None


def test_quota_invalid_values_rejected(client):
    """负数上限 / 未知学科 → 422。"""
    _ptoken, child, _ctoken = _setup(client, "tq4_parent", "tq4_kid")
    r = _set_quota(client, _ptoken, child["id"], {"daily_ask_limit": -1})
    assert r.status_code == 422
    r = _set_quota(
        client, _ptoken, child["id"], {"allowed_subjects": ["物理"]}
    )
    assert r.status_code == 422


def test_quota_other_parent_403(client):
    """越权：别的家长不能设置/查看这个娃娃的管控。"""
    _ptoken, child, _ctoken = _setup(client, "tq5_parent", "tq5_kid")
    other = register_parent(client, username="tq5_other")
    other_token = other.json()["access_token"]

    r = _set_quota(
        client, other_token, child["id"], {"daily_ask_limit": 1}
    )
    assert r.status_code == 403
    r = client.get(
        "/api/v1/tutor/quota",
        headers=auth_headers(other_token),
        params={"child_id": child["id"]},
    )
    assert r.status_code == 403


def test_quota_child_cannot_set(client):
    """娃娃不能自己改管控（403）。"""
    _ptoken, child, ctoken = _setup(client, "tq6_parent", "tq6_kid")
    r = _set_quota(client, ctoken, child["id"], {"daily_ask_limit": 999})
    assert r.status_code == 403


# —— enforcement ——
def test_subject_scope_enforced(client):
    """学科越界：英语提问被 403 拒绝并提示（故事 26）。"""
    _ptoken, child, ctoken = _setup(client, "tq7_parent", "tq7_kid")
    r = _set_quota(
        client, _ptoken, child["id"], {"allowed_subjects": ["数学", "语文"]}
    )
    assert r.status_code == 200

    blocked = _ask(client, ctoken, subject="英语")
    assert blocked.status_code == 403
    # ErrorResp: {"code":..., "message":..., "status":..., "data":null}
    assert "数学" in blocked.json()["message"]

    ok = _ask(client, ctoken, subject="数学")
    assert ok.status_code == 200


def test_per_child_ask_limit_overrides_global(client, monkeypatch):
    """按娃次数上限覆盖全局：设 1 次后第二次 429。"""
    monkeypatch.setattr(settings, "TUTOR_DAILY_LIMIT", 50)
    _ptoken, child, ctoken = _setup(client, "tq8_parent", "tq8_kid")
    r = _set_quota(client, _ptoken, child["id"], {"daily_ask_limit": 1})
    assert r.status_code == 200

    first = _ask(client, ctoken)
    assert first.status_code == 200
    second = _ask(client, ctoken)
    assert second.status_code == 429
    assert "上限" in second.json()["message"]


def test_ask_limit_zero_disables_tutor(client):
    """0 = 今日禁用：第一次提问即被 429 拒。"""
    _ptoken, child, ctoken = _setup(client, "tq9_parent", "tq9_kid")
    _set_quota(client, _ptoken, child["id"], {"daily_ask_limit": 0})
    r = _ask(client, ctoken)
    assert r.status_code == 429


def test_time_limit_zero_disables_tutor(client):
    """时长上限 0 = 今日禁用（used_seconds=0 已 >= 0 分钟）→ 429。"""
    _ptoken, child, ctoken = _setup(client, "tq10_parent", "tq10_kid")
    _set_quota(client, _ptoken, child["id"], {"daily_minutes_limit": 0})
    r = _ask(client, ctoken)
    assert r.status_code == 429
    assert "时长" in r.json()["message"]


def test_usage_accumulates_and_reports(client, monkeypatch):
    """答疑后用量累计：次数 +1，秒数 >= 0；usage 接口回带生效限额。"""
    monkeypatch.setattr(settings, "TUTOR_DAILY_LIMIT", 50)
    _ptoken, child, ctoken = _setup(client, "tq11_parent", "tq11_kid")
    _set_quota(
        client, _ptoken, child["id"], {"daily_ask_limit": 9, "daily_minutes_limit": 30}
    )
    r = _ask(client, ctoken)
    assert r.status_code == 200

    usage = client.get(
        "/api/v1/tutor/usage",
        headers=auth_headers(_ptoken),
        params={"child_id": child["id"]},
    )
    assert usage.status_code == 200
    body = usage.json()
    assert body["asks_today"] == 1
    assert body["used_seconds"] >= 0
    assert body["ask_limit"] == 9
    assert body["minutes_limit"] == 30


def test_usage_reports_global_default_without_quota(client, monkeypatch):
    monkeypatch.setattr(settings, "TUTOR_DAILY_LIMIT", 42)
    _ptoken, child, _ctoken = _setup(client, "tq12_parent", "tq12_kid")
    usage = client.get(
        "/api/v1/tutor/usage",
        headers=auth_headers(_ptoken),
        params={"child_id": child["id"]},
    )
    assert usage.status_code == 200
    assert usage.json()["ask_limit"] == 42
    assert usage.json()["minutes_limit"] is None


def test_usage_other_parent_403(client):
    _ptoken, child, _ctoken = _setup(client, "tq13_parent", "tq13_kid")
    other = register_parent(client, username="tq13_other")
    r = client.get(
        "/api/v1/tutor/usage",
        headers=auth_headers(other.json()["access_token"]),
        params={"child_id": child["id"]},
    )
    assert r.status_code == 403
