"""引擎失败归因与密钥解密契约（ADR-0038）——事故回归。

## 事故现场

用户看到「**当前模型不支持工具调用**：GenkitError: INTERNAL: … Error code: 401 -
Authentication Fails, Your api key: ****xOOR is invalid」。三层缺陷叠出来的假象：

1. ``app.core.crypto.decrypt`` 在 ``InvalidToken`` 时**返回密文原文**——密钥轮换
   （根目录 ``.env`` 被改名，``SECRET_KEY`` 从 ``dev-secret-change-me`` 漂到
   ``changeme``）后旧密文再也解不动，于是 **Fernet 密文被当成 API Key 发给 DeepSeek**。
   厂商回包里的 ``****xOOR`` 正是密文尾号，不是任何真实密钥的尾号。
2. ``agent_core/adapters/genkit.py`` 把**任意**引擎异常无差别包成
   ``ToolUnsupportedError``，于是 401 认证失败被报成「模型不支持工具调用」。
3. 出题 / 批改路径的 ``except Exception`` 进一步把原因抹成「请添加模型」。

本文件把这些不变量钉住：**密文永不出门**、**401 永不被说成「不支持工具调用」**。
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
from types import SimpleNamespace

import pytest
from cryptography.fernet import Fernet
from sqlmodel import Session

from agent_core.adapters.genkit import GenkitEngine, GenkitLLMProvider, classify_failure
from agent_core.errors import ProviderRequestError, ToolUnsupportedError
from agent_core.ports import LLMProvider, TextDelta
from agent_core.protocol import EVENT_ASSISTANT_MESSAGE, EVENT_ERROR
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools
from agent_core.tools import ToolSpec
from app.ai.engine import resolve_engine
from app.core import crypto
from app.db.models import ModelConfig, User

# 剪切板原文（GBK 前缀后的整段）：真实厂商回包，作为本回归的固定输入。
INCIDENT_401 = (
    "GenkitError: INTERNAL: Error while running action openai/deepseek-v4-flash: "
    "Error code: 401 - {'error': {'message': 'Authentication Fails, Your api key: "
    "****xOOR is invalid', 'type': 'authentication_error', 'param': None, "
    "'code': 'invalid_request_error'}}"
)


# ───────────────────────── A) 归类：401 ≠ 不支持工具调用 ─────────────────────────


def test_incident_401_is_classified_as_auth_not_tool_unsupported() -> None:
    """事故回归：401 必须归到 auth，绝不能归成「不支持工具调用」。"""
    failure = classify_failure(RuntimeError(INCIDENT_401))

    assert isinstance(failure, ProviderRequestError)
    assert failure.kind == "auth"
    # 报文里同时出现 invalid_request_error（400 标记），但 auth 优先——否则用户会被
    # 引导去「换模型」而不是「改密钥」。
    assert "不支持工具调用" not in failure.user_hint
    assert "API Key" in failure.user_hint
    assert "模型管理" in failure.user_hint


def test_genuine_tool_unsupported_stays_tool_unsupported() -> None:
    """模型真没有 function calling 时仍走 TOOL_UNSUPPORTED（ADR-0033 不退化）。"""
    failure = classify_failure(RuntimeError("tool calling 不被支持"))

    assert isinstance(failure, ToolUnsupportedError)
    assert failure.reason.endswith("tool calling 不被支持")


@pytest.mark.parametrize(
    ("payload", "kind"),
    [
        ("Error code: 429 - rate limit exceeded", "rate_limit"),
        ("APIConnectionError: Connection error.", "network"),
        ("Error code: 400 - invalid_request_error: bad payload", "bad_request"),
        ("something inexplicable happened", "unknown"),
    ],
)
def test_failure_kind_classification(payload: str, kind: str) -> None:
    """限流 / 网络 / 参数被拒 / 未知各有归类，默认落到 unknown（不误报能力问题）。"""
    failure = classify_failure(RuntimeError(payload))

    assert isinstance(failure, ProviderRequestError)
    assert failure.kind == kind


# ───────────────────────── B) 适配器：三条分支都归类 ─────────────────────────


class _RaisingEngine:
    """generate_stream 一调用就抛（模拟厂商拒绝）。"""

    def __init__(self, exc: BaseException) -> None:
        self._exc = exc

    def generate_stream(self, **_kwargs):  # noqa: ANN003 — duck-typing 适配器入参
        raise self._exc


def _engine(exc: BaseException) -> GenkitEngine:
    return GenkitEngine(genkit=_RaisingEngine(exc), model="openai/deepseek-v4-flash")


def _run(engine: GenkitEngine, **kw):
    async def _collect():
        return [ev async for ev in GenkitLLMProvider(engine).stream("sys", "usr", **kw)]

    return asyncio.run(_collect())


def test_tools_branch_reports_provider_error_not_tool_unsupported() -> None:
    """工具分支：401 抛 ProviderRequestError（历史 bug 在此处抛 ToolUnsupportedError）。"""
    with pytest.raises(ProviderRequestError) as ei:
        _run(_engine(RuntimeError(INCIDENT_401)), tools=[{"name": "list_x"}])

    assert ei.value.kind == "auth"


def test_schema_branch_also_classified() -> None:
    """schema（出题）分支同样归类——否则原始 GenkitError 会被上层笼统吞掉。"""
    with pytest.raises(ProviderRequestError) as ei:
        _run(_engine(RuntimeError(INCIDENT_401)), schema=SimpleNamespace())

    assert ei.value.kind == "auth"


def test_plain_branch_also_classified() -> None:
    """纯文本（伴学）分支同样归类。"""
    with pytest.raises(ProviderRequestError) as ei:
        _run(_engine(RuntimeError(INCIDENT_401)))

    assert ei.value.kind == "auth"


# ───────────────────────── C) subagent：PROVIDER_ERROR 帧 ─────────────────────────


class _RaisingProvider(LLMProvider):
    """首轮即抛指定异常的替身 provider（不触真实模型）。"""

    def __init__(self, exc: Exception) -> None:
        self._exc = exc
        self.calls = 0

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        self.calls += 1
        raise self._exc
        yield TextDelta(delta="")  # pragma: no cover — 让本方法成为异步生成器


class _Agent(BaseSubAgent):
    business = "attribution_test"

    def __init__(self, *, provider, tools=()) -> None:
        super().__init__(provider=provider)
        self.tools = list(tools)

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        yield self._finish("noop")


def _spec() -> ToolSpec:
    async def _handler(args, *, ctx, session=None):
        return {"ok": True}

    return ToolSpec(
        name="list_x",
        description="查询 list_x",
        schema={"type": "object", "properties": {}},
        handler=_handler,
    )


def test_subagent_emits_provider_error_frame_with_actionable_hint() -> None:
    """厂商拒绝 → ERROR(code=PROVIDER_ERROR) + 可操作提示，且不得再出现「不支持工具调用」。"""
    provider = _RaisingProvider(ProviderRequestError(INCIDENT_401, kind="auth"))
    agent = _Agent(provider=provider, tools=[_spec()])

    events = asyncio.run(
        _collect(agent)
    )

    errs = [ev for ev in events if ev.eventType == EVENT_ERROR]
    assert len(errs) == 1
    assert errs[0].code == "PROVIDER_ERROR"
    assert "API Key" in (errs[0].message or "")
    assert "不支持工具调用" not in (errs[0].message or "")
    # 硬失败：不得继续产出助手文本（否则模型会凭空编造业务数据）
    assert EVENT_ASSISTANT_MESSAGE not in [ev.eventType for ev in events]
    assert provider.calls == 1, "硬失败后不得重试"


def test_subagent_keeps_both_failure_messages_apart() -> None:
    """两条失败语义必须各有各的话：TOOL_UNSUPPORTED ≠ PROVIDER_ERROR。"""
    tool_err = _first_error(
        _Agent(
            provider=_RaisingProvider(ToolUnsupportedError("no function calling")),
            tools=[_spec()],
        )
    )
    provider_err = _first_error(
        _Agent(
            provider=_RaisingProvider(ProviderRequestError(INCIDENT_401, kind="auth")),
            tools=[_spec()],
        )
    )

    assert tool_err.code == "TOOL_UNSUPPORTED"
    assert "不支持工具调用" in (tool_err.message or "")
    assert provider_err.code == "PROVIDER_ERROR"
    assert "不支持工具调用" not in (provider_err.message or "")


def _first_error(agent):
    events = asyncio.run(_collect(agent))
    errs = [ev for ev in events if ev.eventType == EVENT_ERROR]
    assert len(errs) == 1, f"应恰好一个 ERROR 帧，实得 {len(errs)}"
    return errs[0]


async def _collect(agent):
    return [ev async for ev in run_with_tools(agent, "查一下", SubAgentContext())]


# ───────────────────────── D) 密钥：密文永不出门 ─────────────────────────


def _fernet_for(secret: str) -> Fernet:
    return Fernet(base64.urlsafe_b64encode(hashlib.sha256(secret.encode()).digest()))


def test_decrypt_failure_returns_none_never_ciphertext(monkeypatch) -> None:
    """事故回归：密钥轮换后旧密文解不开 → 返回 None，**绝不**把密文当密钥返回。"""
    monkeypatch.setattr(crypto.settings, "MODEL_APIKEY_SECRET", "", raising=False)
    monkeypatch.setattr(crypto.settings, "SECRET_KEY", "dev-secret-change-me", raising=False)
    cipher = crypto.encrypt("sk-real-key")
    assert cipher is not None and cipher != "sk-real-key"

    # 模拟 .env 被改名 / SECRET_KEY 漂移
    monkeypatch.setattr(crypto.settings, "SECRET_KEY", "changeme", raising=False)
    out = crypto.decrypt(cipher)

    assert out is None, "解不开必须视为未配置密钥"
    assert out != cipher, "密文不得外泄（曾以此为 API Key 请求厂商 → 401 + 凭据泄露）"


def test_decrypt_roundtrip_with_same_secret(monkeypatch) -> None:
    monkeypatch.setattr(crypto.settings, "MODEL_APIKEY_SECRET", "", raising=False)
    monkeypatch.setattr(crypto.settings, "SECRET_KEY", "s1", raising=False)

    assert crypto.decrypt(crypto.encrypt("sk-abc")) == "sk-abc"


def test_decrypt_without_any_secret_is_plaintext_passthrough(monkeypatch) -> None:
    """完全未配置密钥时保持明文兜底（与 encrypt 对称）——开发期行为不破坏。"""
    monkeypatch.setattr(crypto.settings, "MODEL_APIKEY_SECRET", "", raising=False)
    monkeypatch.setattr(crypto.settings, "SECRET_KEY", "", raising=False)

    assert crypto.encrypt("sk-plain") == "sk-plain"
    assert crypto.decrypt("sk-plain") == "sk-plain"


# ───────────────────────── E) 引擎解析：密文不落到 provider ─────────────────────────


def _capture_engine_kwargs(monkeypatch) -> list[dict]:
    captured: list[dict] = []

    def _fake_build(**kwargs):
        captured.append(kwargs)
        return SimpleNamespace(genkit=object(), model=f"{kwargs['provider']}/{kwargs['model_name']}")

    monkeypatch.setattr("app.ai.engine.build_genkit_engine", _fake_build)
    return captured


def test_resolve_engine_never_passes_stored_ciphertext_as_api_key(
    db: Session, monkeypatch
) -> None:
    """ModelConfig 存了**解不开**的密文时，传给引擎的 api_key 必须为空，而非密文。"""
    monkeypatch.setattr(crypto.settings, "MODEL_APIKEY_SECRET", "", raising=False)
    monkeypatch.setattr(crypto.settings, "SECRET_KEY", "changeme", raising=False)
    captured = _capture_engine_kwargs(monkeypatch)

    parent = User(
        username="rot@p.com", display_name="轮换家长", role="parent",
        hashed_password="x", parent_id=None,
    )
    db.add(parent)
    db.commit()
    db.refresh(parent)
    # 用「另一个密钥」加密 → 现在解不开（正是用户现场）
    stale = _fernet_for("dev-secret-change-me").encrypt(b"sk-stale").decode()
    mc = ModelConfig(
        parent_id=parent.id, provider="openai_compat", model_name="deepseek-v4-flash",
        api_key_enc=stale, base_url="https://api.deepseek.com", label="deepseek",
        is_default=True,
    )
    db.add(mc)
    db.commit()
    db.refresh(mc)

    engine = resolve_engine(str(mc.id), parent_id=str(parent.id), session=db)

    assert engine is not None
    assert captured, "应经 build_genkit_engine 构造引擎"
    assert captured[0]["api_key"] is None
    assert stale not in str(captured[0]), "密文不得出现在任何传给引擎的参数里"


def test_resolve_engine_passes_decrypted_key_when_secret_matches(
    db: Session, monkeypatch
) -> None:
    """密钥匹配时必须真的把明文密钥交出去（别把「安全」修成「一直没密钥」）。"""
    monkeypatch.setattr(crypto.settings, "MODEL_APIKEY_SECRET", "", raising=False)
    monkeypatch.setattr(crypto.settings, "SECRET_KEY", "s-match", raising=False)
    captured = _capture_engine_kwargs(monkeypatch)

    parent = User(
        username="ok@p.com", display_name="正常家长", role="parent",
        hashed_password="x", parent_id=None,
    )
    db.add(parent)
    db.commit()
    db.refresh(parent)
    mc = ModelConfig(
        parent_id=parent.id, provider="openai_compat", model_name="gpt-4o-mini",
        api_key_enc=crypto.encrypt("sk-plain-key"), label="ok", is_default=True,
    )
    db.add(mc)
    db.commit()
    db.refresh(mc)

    resolve_engine(str(mc.id), parent_id=str(parent.id), session=db)

    assert captured[0]["api_key"] == "sk-plain-key"
