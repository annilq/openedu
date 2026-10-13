"""api_key 加密（ADR-0015 / 票据 08）：ModelConfig.api_key 必须加密存储。

派生 Fernet 密钥：**唯一来源**是 ``settings.MODEL_APIKEY_SECRET``——**绝不**回落
通用会话签名密钥。历史上 ``MODEL_APIKEY_SECRET or <通用密钥>`` 的静默回退会在未配
专用密钥时把 api_key 落到通用密钥下，属无声降安全级（密钥来源不单一、轮换语义混乱），
故移除（票据 07 / LCC-07）。

密钥缺失时的行为（单一来源原则下的边界）：
- **开发环境** (``FASTAPI_ENV == "development"``)：记 warning 后走明文兜底（不加密、原样返回），
  便利本地联调；
- **非开发环境**（生产）：启动期直接 **fail-fast**——``_fernet`` 抛 ``CryptoConfigError``，
  由 ``app.main`` 的 lifespan 健康检查（``check_runtime_secrets_health``）在启动即阻断，
  绝不带着错误密钥来源偷偷起服。

**解密失败的契约（ADR-0038）**：只能返回 ``None``，**绝不回退密文原文**、绝不抛错或翻译成
「请添加模型」。历史 bug：``InvalidToken`` 时返回 ``token`` 本身，于是 Fernet 密文被当作 API Key
透传给厂商 → 401 + 密文外泄（事故现场：厂商回包 ``Your api key: ****xOOR``，
``xOOR`` 正是密文尾号）。密文解不开的常见原因是**密钥轮换**（MODEL_APIKEY_SECRET 变更后，
旧密文再也解不动），此时正确语义是「该模型没有可用密钥」，由调用方按「未配置密钥」处理
（``resolve_engine`` 传入 ``api_key=None``）。
"""
from __future__ import annotations

import base64
import hashlib
import logging

from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings

logger = logging.getLogger(__name__)


class CryptoConfigError(RuntimeError):
    """密钥来源配置错误：非开发环境下 ``MODEL_APIKEY_SECRET`` 缺失。

    属启动期配置错误（fail-fast），由 lifespan 健康检查在 ``_fernet`` 首次被触发的
    启动路径上暴露；正常运行期（启动已通过）不会抛出——因为启动已保证密钥已配置。
    """


def _fernet() -> Fernet | None:
    """派生 Fernet 实例；密钥来源**仅** ``MODEL_APIKEY_SECRET``。

    - 密钥存在 → 返回派生出的 ``Fernet``；
    - 开发环境且密钥缺失 → 记 warning 并返回 ``None``（调用方走明文兜底）；
    - 非开发环境且密钥缺失 → 抛 ``CryptoConfigError``（启动期配置错误，fail-fast）。
    """
    secret = settings.MODEL_APIKEY_SECRET
    if not secret:
        if settings.FASTAPI_ENV == "development":
            logger.warning(
                "MODEL_APIKEY_SECRET 未配置：开发环境走明文兜底（api_key 不加密落库），"
                "仅本地联调可用；生产环境必须显式配置 MODEL_APIKEY_SECRET，否则启动失败。"
            )
            return None
        raise CryptoConfigError(
            "MODEL_APIKEY_SECRET 未配置：非开发环境必须显式配置专用加密密钥，"
            "禁止回落通用会话签名密钥（已去除静默降安全级回退）。详见 ADR-0038。"
        )
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
            "api_key 解密失败：MODEL_APIKEY_SECRET 可能已变更（密钥轮换），"
            "该模型视为未配置密钥，请在「模型管理」中重新填写。"
        )
        return None
