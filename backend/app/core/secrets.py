"""启动期密钥健康检查（ADR-0038 / ADR-0041：密钥问题应在启动期暴露，而非提问时才 401）。

在 ``app.main`` 的 lifespan 中调用 ``check_runtime_secrets_health``：
- 生产环境：``SECRET_KEY`` / ``MODEL_APIKEY_SECRET`` 不得为默认/空值，否则阻断启动；
- 对每张 ModelConfig 尝试解密 ``api_key_enc``，解不开即密钥已轮换，启动期 WARN 点名模型，
  避免用户提问/出题时才爆 401（现场：厂商回包泄露密文尾号 ``xOOR``）。
"""
from __future__ import annotations

import logging

from sqlmodel import Session, select

from app.core.config import settings
from app.core.crypto import decrypt
from app.db.models import ModelConfig

logger = logging.getLogger(__name__)


def check_runtime_secrets_health(session: Session) -> None:
    """校验密钥可用性，尽早暴露密钥轮换 / 缺配问题。

    设计要点：
    - 生产环境缺配（默认 SECRET_KEY 或空 MODEL_APIKEY_SECRET）直接抛错阻断启动，
      而非在请求期才暴露。
    - 开发环境仅对仍用默认 SECRET_KEY 的情况告警。
    - 对已落库的 ModelConfig 做解密冒烟：``decrypt`` 在解不开时返回 ``None``
      （ADR-0038 契约，绝不回退密文），命中即记 WARNING 并点名模型 id。
    """
    insecure = settings.SECRET_KEY in (None, "", "changeme")
    no_model_secret = not settings.MODEL_APIKEY_SECRET
    if settings.FASTAPI_ENV == "production" and (insecure or no_model_secret):
        raise RuntimeError(
            "启动密钥健康检查未通过：生产环境必须显式配置 SECRET_KEY 与 MODEL_APIKEY_SECRET，"
            "禁止沿用默认/空值（详见 ADR-0038 / ADR-0041 密钥治理）。"
        )
    if insecure:
        logger.warning(
            "SECRET_KEY 仍为默认/空值，仅开发期可用；部署到生产前务必显式配置。"
        )

    rows = session.exec(select(ModelConfig)).all()
    if not rows:
        return
    broken: list[str] = []
    for mc in rows:
        # decrypt 解不开（密钥轮换 / 密文损坏）→ None；明文兜底场景返回原值（truthy）不误报
        if mc.api_key_enc and decrypt(mc.api_key_enc) is None:
            broken.append(str(mc.id))
    if broken:
        logger.warning(
            "检测到 %d 个模型的 api_key 解密失败（密钥已轮换？），将在提问/出题时按未配置处理：%s",
            len(broken),
            ", ".join(broken),
        )
