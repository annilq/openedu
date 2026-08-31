"""api_key 加密（ADR-0015 / 票据 08）：ModelConfig.api_key 必须加密存储。

派生 Fernet 密钥：优先用 settings.MODEL_APIKEY_SECRET；缺省时回退用 SECRET_KEY
做 SHA-256 → base64（开发期便利，生产须显式配置 MODEL_APIKEY_SECRET）。
未配置密钥时不抛错，明文兜底（仅开发期），生产务必配置。
"""
from __future__ import annotations

import base64
import hashlib

from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings


def _fernet() -> Fernet | None:
    secret = settings.MODEL_APIKEY_SECRET or settings.SECRET_KEY
    if not secret:
        return None
    digest = hashlib.sha256(secret.encode()).digest()
    key = base64.urlsafe_b64encode(digest)
    return Fernet(key)


def encrypt(plain: str | None) -> str | None:
    if plain is None:
        return None
    f = _fernet()
    if f is None:
        return plain  # 无密钥：明文兜底（开发期）
    return f.encrypt(plain.encode()).decode()


def decrypt(token: str | None) -> str | None:
    if token is None:
        return None
    f = _fernet()
    if f is None:
        return token
    try:
        return f.decrypt(token.encode()).decode()
    except (InvalidToken, ValueError):
        return token  # 解密失败（如密钥轮换）回退原文，调用方按缺失处理
