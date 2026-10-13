"""crypto 单测（票据 07 / LCC-07）：单一密钥来源 ``MODEL_APIKEY_SECRET``。

覆盖 ``_fernet()`` 的三态：
- (a) 密钥存在 → 派生出可用 Fernet（加解密往返）；
- (b) 开发环境密钥缺失 → warning + 明文兜底（``None``）；
- (c) 非开发环境密钥缺失 → fail-fast（抛 ``CryptoConfigError``）。
同时守住 ADR-0038：``decrypt`` 解不开只返 ``None``。
"""
from __future__ import annotations

import logging

import pytest

from app.core import crypto
from app.core.crypto import CryptoConfigError, _fernet


def test_fernet_derives_key_when_secret_present(monkeypatch):
    monkeypatch.setattr("app.core.config.settings.MODEL_APIKEY_SECRET", "my-secret")
    monkeypatch.setattr("app.core.config.settings.FASTAPI_ENV", "production")
    f = _fernet()
    assert f is not None
    # 同一密钥可加解密往返
    enc = f.encrypt(b"sk-abc")
    assert f.decrypt(enc).decode() == "sk-abc"


def test_fernet_plaintext_in_dev_when_secret_missing(monkeypatch, caplog):
    monkeypatch.setattr("app.core.config.settings.MODEL_APIKEY_SECRET", "")
    monkeypatch.setattr("app.core.config.settings.FASTAPI_ENV", "development")
    with caplog.at_level(logging.WARNING):
        assert _fernet() is None
    assert any("MODEL_APIKEY_SECRET" in r.message for r in caplog.records)


def test_fernet_fails_fast_in_non_dev_when_secret_missing(monkeypatch):
    monkeypatch.setattr("app.core.config.settings.MODEL_APIKEY_SECRET", "")
    monkeypatch.setattr("app.core.config.settings.FASTAPI_ENV", "production")
    with pytest.raises(CryptoConfigError):
        _fernet()


def test_encrypt_decrypt_plaintext_fallback_in_dev(monkeypatch):
    # 开发环境缺密钥：明文兜底，encrypt 不加密、decrypt 原样返回（对称）
    monkeypatch.setattr("app.core.config.settings.MODEL_APIKEY_SECRET", "")
    monkeypatch.setattr("app.core.config.settings.FASTAPI_ENV", "development")
    assert crypto.encrypt("sk-1") == "sk-1"
    assert crypto.decrypt("sk-1") == "sk-1"
    assert crypto.decrypt(None) is None


def test_decrypt_returns_none_on_undecryptable_token(monkeypatch, caplog):
    # ADR-0038：密文但解不开（密钥轮换）→ None，绝不回退密文原文
    monkeypatch.setattr("app.core.config.settings.MODEL_APIKEY_SECRET", "secret-A")
    ct = crypto.encrypt("sk-123")
    monkeypatch.setattr("app.core.config.settings.MODEL_APIKEY_SECRET", "secret-B")
    with caplog.at_level(logging.WARNING):
        assert crypto.decrypt(ct) is None
    assert any("解密失败" in r.message for r in caplog.records)
