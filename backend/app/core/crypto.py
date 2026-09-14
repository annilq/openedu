"""api_key 加密（ADR-0015 / 票据 08）：ModelConfig.api_key 必须加密存储。

派生 Fernet 密钥：优先用 settings.MODEL_APIKEY_SECRET；缺省时回退用 SECRET_KEY
做 SHA-256 → base64（开发期便利，生产须显式配置 MODEL_APIKEY_SECRET）。
未配置密钥时不抛错，明文兜底（仅开发期），生产务必配置。

**解密失败的契约（ADR-0038）**：只能返回 ``None``，**绝不回退密文原文**。
历史 bug：``InvalidToken`` 时返回 ``token`` 本身，于是 Fernet 密文被当作 API Key
透传给厂商 → 401 + 密文外泄（事故现场：厂商回包 ``Your api key: ****xOOR``，
``xOOR`` 正是密文尾号）。密文解不开的常见原因是**密钥轮换**（SECRET_KEY /
MODEL_APIKEY_SECRET 变更后，旧密文再也解不动），此时正确语义是「该模型没有可用密钥」，
由调用方按「未配置密钥」处理（``resolve_engine`` 传入 ``api_key=None``）。
"""
from __future__ import annotations

import base64
import hashlib
import logging

from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings

logger = logging.getLogger(__name__)


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
    """解密 api_key；解不开时返回 ``None``（调用方视为「没配密钥」）。

    - 未配置任何密钥 → 明文兜底，原样返回（与 ``encrypt`` 对称）；
    - 密文但解不开（密钥轮换 / 密文损坏）→ 记 warning 后返回 ``None``。
      **不得返回密文**：那会把密文当凭据发给厂商，既是功能故障也是凭据外泄。
    """
    if token is None:
        return None
    f = _fernet()
    if f is None:
        return token
    try:
        return f.decrypt(token.encode()).decode()
    except (InvalidToken, ValueError):
        logger.warning(
            "api_key 解密失败：MODEL_APIKEY_SECRET / SECRET_KEY 可能已变更（密钥轮换），"
            "该模型视为未配置密钥，请在「模型管理」中重新填写。"
        )
        return None
