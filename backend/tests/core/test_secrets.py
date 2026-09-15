"""密钥健康检查 / SECRET_KEY 持久化 / DATABASE_URL 归一 的单测（④ 三个遗留项修复）。"""
from __future__ import annotations

import logging
import uuid

import pytest
from sqlmodel import Session, SQLModel, create_engine

from app.core.config import Settings, _normalize_db_url, resolve_effective_secret_key
from app.core.secrets import check_runtime_secrets_health
from app.db.models import ModelConfig


# ── resolve_effective_secret_key ──────────────────────────────────────────────
class _MemFile:
    """内存桩，模拟落盘文件，避免依赖 tmp_path（沙箱 broker 禁止重建临时目录）。"""

    def __init__(self) -> None:
        self._data: str | None = None

    def exists(self) -> bool:
        return self._data is not None

    def read_text(self) -> str:
        return self._data or ""

    def write_text(self, text: str) -> None:
        self._data = text


class _ReadOnlyFile:
    """写入即失败的桩，模拟只读文件系统（容器 / CI）。"""

    def exists(self) -> bool:
        return False

    def read_text(self) -> str:
        return ""

    def write_text(self, text: str) -> None:
        raise OSError("read-only")


def test_resolve_secret_key_keeps_explicit():
    assert resolve_effective_secret_key("real-key") == "real-key"


def test_resolve_secret_key_generates_and_persists():
    f = _MemFile()
    k1 = resolve_effective_secret_key("changeme", file_path=f)
    assert k1 and k1 != "changeme"
    assert f.read_text().strip() == k1
    # 复用落盘密钥，重启（再次调用）后值稳定，登录态不失效
    assert resolve_effective_secret_key(None, file_path=f) == k1


def test_resolve_secret_key_readonly_falls_back():
    f = _ReadOnlyFile()
    k = resolve_effective_secret_key(None, file_path=f)
    assert k and k != "changeme"


# ── _normalize_db_url ─────────────────────────────────────────────────────────
def test_db_url_relative_resolved_to_backend():
    out = _normalize_db_url("sqlite:///./app.db")
    assert out.startswith("sqlite:////")  # 4 斜杠 = 绝对路径
    assert "backend" in out


def test_db_url_absolute_untouched():
    assert _normalize_db_url("sqlite:////abs/app.db") == "sqlite:////abs/app.db"


def test_db_url_postgres_scheme_rewritten():
    assert _normalize_db_url("postgres://h/db") == "postgresql+psycopg://h/db"


def test_settings_default_db_url_is_absolute():
    # 默认 DATABASE_URL 必须是绝对路径（CWD 无关）
    assert Settings().DATABASE_URL.startswith("sqlite:////")


# ── check_runtime_secrets_health ──────────────────────────────────────────────
@pytest.fixture
def mem_session():
    eng = create_engine("sqlite://")
    SQLModel.metadata.create_all(eng)
    with Session(eng) as s:
        yield s


def test_health_check_empty_table_passes(mem_session):
    check_runtime_secrets_health(mem_session)  # 不应抛


def test_health_check_prod_missing_secrets_raises(mem_session, monkeypatch):
    monkeypatch.setattr("app.core.config.settings.FASTAPI_ENV", "production")
    monkeypatch.setattr("app.core.config.settings.SECRET_KEY", "changeme")
    monkeypatch.setattr("app.core.config.settings.MODEL_APIKEY_SECRET", "")
    with pytest.raises(RuntimeError):
        check_runtime_secrets_health(mem_session)


def test_health_check_flags_undecryptable_model(mem_session, caplog, monkeypatch):
    # 模拟密钥轮换：用密钥 A 加密，健康检查用密钥 B 解密 → 解不开 → 记 WARNING
    from app.core import crypto

    monkeypatch.setattr("app.core.config.settings.MODEL_APIKEY_SECRET", "secret-A")
    ct = crypto.encrypt("sk-123")
    monkeypatch.setattr("app.core.config.settings.MODEL_APIKEY_SECRET", "secret-B")

    mc = ModelConfig(
        id=uuid.uuid4(),
        parent_id=uuid.uuid4(),
        label="x",
        provider="openai_compat",
        model_name="gpt",
        api_key_enc=ct,
    )
    mem_session.add(mc)
    mem_session.commit()

    with caplog.at_level(logging.WARNING):
        check_runtime_secrets_health(mem_session)
    assert any("解密失败" in r.message for r in caplog.records)
