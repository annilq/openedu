"""「测试连接」（POST /models/test）守卫：不落库试连、密钥取自库里、归因与超时。

**全套件不得真实调用模型**（conftest 的 ``fake_llm`` 只覆盖助手端点，本端点自行
打桩）：这里打的是 ``probe`` 模块自己的引擎构造与调用两个接缝，因此不联网、
也不依赖本机是否装了 Ollama。
"""
from __future__ import annotations

import asyncio

import pytest

from agent_core.errors import ProviderRequestError
from app.core.config import settings
from app.features.model_management import probe as probe_mod
from tests.utils.user import auth_headers, login, register_parent


def _parent(client, suffix="p1"):
    register_parent(client, username=f"parent_{suffix}", password="pw123456")
    token = login(client, f"parent_{suffix}", "pw123456").json()["access_token"]
    return auth_headers(token)


def _create(client, headers, **overrides) -> dict:
    payload = {
        "label": "M",
        "provider": "ollama",
        "base_url": "http://localhost:11434",
        "model_name": "llama3",
        "api_key": "sk-stored",
    }
    payload.update(overrides)
    r = client.post("/api/v1/models", headers=headers, json=payload)
    assert r.status_code == 201, r.text
    return r.json()


@pytest.fixture
def recorder(monkeypatch):
    """截获探针收到的最终参数（不打真实引擎），并允许注入结果。"""
    calls: list[dict] = []
    outcome = {"resp": None}

    async def _fake_probe(**kwargs):
        calls.append(kwargs)
        if outcome["resp"] is not None:
            return outcome["resp"]
        from app.features.model_management.schemas import ModelProbeResp

        return ModelProbeResp(ok=True, latency_ms=1, message="连接成功")

    monkeypatch.setattr(probe_mod, "probe_model", _fake_probe)
    monkeypatch.setattr(
        "app.features.model_management.router.probe_model", _fake_probe
    )
    return calls, outcome


def test_probe_inline_params(client, recorder):
    """新增表单：只带表单参数，密钥用请求里那份明文。"""
    calls, _ = recorder
    r = client.post(
        "/api/v1/models/test",
        headers=_parent(client, "inline"),
        json={
            "provider": "openai_compat",
            "base_url": "https://api.deepseek.com",
            "model_name": "deepseek-v4-flash",
            "api_key": "sk-typed",
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["ok"] is True
    assert calls[0]["api_key"] == "sk-typed"
    assert calls[0]["model_name"] == "deepseek-v4-flash"


def test_probe_uses_stored_key_when_blank(client, recorder):
    """编辑表单密钥留空 = 用库里解密出来的那份（前端自己做不到的那一半）。"""
    calls, _ = recorder
    h = _parent(client, "stored")
    created = _create(client, h, api_key="sk-stored")
    r = client.post(
        "/api/v1/models/test",
        headers=h,
        json={"model_id": created["id"]},
    )
    assert r.status_code == 200, r.text
    assert calls[0]["api_key"] == "sk-stored"
    # 未覆盖的字段回落库里配置
    assert calls[0]["model_name"] == "llama3"
    assert calls[0]["provider"] == "ollama"


def test_probe_override_wins_over_stored(client, recorder):
    """表单里改了模型名就以表单为准（改完还没保存就该试新的）。"""
    calls, _ = recorder
    h = _parent(client, "override")
    created = _create(client, h)
    r = client.post(
        "/api/v1/models/test",
        headers=h,
        json={"model_id": created["id"], "model_name": "qwen3", "api_key": "sk-new"},
    )
    assert r.status_code == 200, r.text
    assert calls[0]["model_name"] == "qwen3"
    assert calls[0]["api_key"] == "sk-new"


def test_probe_other_parents_model_is_404(client, recorder):
    """越权：拿别人的 model_id 试连 → 404（与其余读接口同口径）。"""
    _, _ = recorder
    owner = _parent(client, "owner")
    created = _create(client, owner)
    stranger = _parent(client, "stranger")
    r = client.post(
        "/api/v1/models/test",
        headers=stranger,
        json={"model_id": created["id"]},
    )
    assert r.status_code == 404


def test_probe_requires_provider(client, recorder):
    """既无 provider 也无预设 → 422（与 create 同口径）。"""
    _, _ = recorder
    r = client.post(
        "/api/v1/models/test",
        headers=_parent(client, "novalid"),
        json={"model_name": "gpt-4o", "api_key": "sk-x"},
    )
    assert r.status_code == 422


def test_probe_classifies_provider_failure(client, monkeypatch):
    """厂商 401 → 归因 auth，且**仍是 200 + ok=false**（测不通是正常结论）。

    打桩落在 ``probe`` 内部的调用点而不是 router 的入口，这样「异常 → ModelProbeResp」
    这段真实代码（含 ADR-0038 的策展文案）也在覆盖范围内。
    """

    async def _call_raises(genkit, model):  # noqa: ARG001
        raise ProviderRequestError("Incorrect API key provided", kind="auth")

    monkeypatch.setattr(probe_mod, "_call_once", _call_raises)
    monkeypatch.setattr(
        probe_mod,
        "build_engine",
        lambda **kwargs: type("E", (), {"genkit": None, "model": "openai/x"})(),
    )

    r = client.post(
        "/api/v1/models/test",
        headers=_parent(client, "auth"),
        json={
            "provider": "openai_compat",
            "base_url": "https://api.deepseek.com",
            "model_name": "deepseek-v4-flash",
            "api_key": "sk-bad",
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is False
    assert body["error_kind"] == "auth"
    # 策展文案（ADR-0038），且明文密钥不得出现在回显里
    assert "API Key" in body["message"]


def test_probe_timeout_becomes_conclusion(client, monkeypatch):
    """厂商挂住 → 超时是结论（kind=timeout），不是 500 也不是挂死。"""
    monkeypatch.setattr(settings, "MODEL_PROBE_TIMEOUT_S", 0.01)

    async def _hang(genkit, model):  # noqa: ARG001
        await asyncio.sleep(5)

    monkeypatch.setattr(probe_mod, "_call_once", _hang)
    monkeypatch.setattr(
        probe_mod,
        "build_engine",
        lambda **kwargs: type("E", (), {"genkit": None, "model": "openai/x"})(),
    )

    r = client.post(
        "/api/v1/models/test",
        headers=_parent(client, "timeout"),
        json={
            "provider": "openai_compat",
            "base_url": "https://api.deepseek.com",
            "model_name": "deepseek-v4-flash",
            "api_key": "sk-x",
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is False
    assert body["error_kind"] == "timeout"


class _FakeSresp:
    """genkit ``ModelStreamResponse`` 的最小替身：stream + response(Future)。"""

    def __init__(self, future, chunks: int = 1, tail_sleep: float = 60.0):
        self._future = future
        self._chunks = chunks
        self._tail_sleep = tail_sleep

    @property
    def response(self):
        return self._future

    @property
    def stream(self):
        chunks, tail = self._chunks, self._tail_sleep

        async def _gen():
            for _ in range(chunks):
                yield object()
            # 出过帧之后再「永远」不出帧：若探针还在读完整条流，必然撞超时。
            # 一帧未出（后台已失败）时立即收尾——真实 channel 此时也是立刻
            # StopAsyncIteration，不会挂住。
            if chunks:
                await asyncio.sleep(tail)

        return _gen()


class _FakeGenkit:
    """generate_stream 替身：Future 在**当前 loop 内**创建（同步测试里建不了）。"""

    def __init__(self, *, chunks: int = 1, fail_with: Exception | None = None):
        self._chunks = chunks
        self._fail_with = fail_with

    def generate_stream(self, **kwargs):  # noqa: ARG002 — 签名匹配即可
        future = asyncio.get_running_loop().create_future()
        if self._fail_with is not None:
            future.set_exception(self._fail_with)
        return _FakeSresp(future, chunks=self._chunks)


def _patch_engine(monkeypatch, genkit):
    monkeypatch.setattr(
        probe_mod,
        "build_engine",
        lambda **kwargs: type("E", (), {"genkit": genkit, "model": "ollama/x"})(),
    )


def test_probe_stops_at_first_chunk(client, monkeypatch):
    """首帧即收工：思维链模型（qwen3 实测 6.4s 才说完）不该拖慢一次握手。

    替身在首帧后 60 秒不再出帧 + 探针超时 2 秒——若有人改回「读完整个流」，
    这个用例必然失败（超时）。
    """
    monkeypatch.setattr(settings, "MODEL_PROBE_TIMEOUT_S", 2.0)
    _patch_engine(monkeypatch, _FakeGenkit(chunks=1))

    r = client.post(
        "/api/v1/models/test",
        headers=_parent(client, "firstchunk"),
        json={
            "provider": "ollama",
            "base_url": "http://localhost:11434",
            "model_name": "qwen3:1.7b",
            "api_key": "",
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is True, body
    assert body["latency_ms"] < 1000  # 没去等那条 60 秒的尾巴


def test_probe_no_chunk_but_failed_is_not_success(client, monkeypatch):
    """开流前就失败（401）不得被判成成功。

    genkit 的 channel 在后台任务异常时只是静默 ``StopAsyncIteration``——
    一帧都没收到却当成「连通」，是最危险的那种假绿灯。
    """
    _patch_engine(
        monkeypatch,
        _FakeGenkit(chunks=0, fail_with=RuntimeError("401 Incorrect API key")),
    )

    r = client.post(
        "/api/v1/models/test",
        headers=_parent(client, "nochunk"),
        json={
            "provider": "openai_compat",
            "base_url": "https://api.deepseek.com",
            "model_name": "deepseek-v4-flash",
            "api_key": "sk-bad",
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is False
    assert body["error_kind"] == "auth"


def test_probe_redacts_secret_from_detail(client, monkeypatch):
    """厂商报错里夹带的密钥明文不得回显（报错要进前端日志与界面）。"""
    async def _boom(genkit, model):  # noqa: ARG001
        raise RuntimeError("bad url https://x.test?key=sk-secret-123 refused")

    monkeypatch.setattr(probe_mod, "_call_once", _boom)
    monkeypatch.setattr(
        probe_mod,
        "build_engine",
        lambda **kwargs: type("E", (), {"genkit": None, "model": "openai/x"})(),
    )

    r = client.post(
        "/api/v1/models/test",
        headers=_parent(client, "redact"),
        json={
            "provider": "openai_compat",
            "base_url": "https://x.test",
            "model_name": "m",
            "api_key": "sk-secret-123",
        },
    )
    body = r.json()
    assert "sk-secret-123" not in (body["detail"] or "")
    assert "***" in (body["detail"] or "")
