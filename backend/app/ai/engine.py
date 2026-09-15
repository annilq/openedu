"""引擎解析（ADR-0015 / ADR-0039）：把「模型引用」解析为可用的引擎 + model 字符串。

**唯一配置源是「模型管理」**（ADR-0039 起）：所有模型都由家长在客户端手动录入，
落 ``ModelConfig`` 表（api_key 经 Fernet 加密）。不再有管理员 ``BUILTIN_MODELS``
内置目录，也不读本地 ``LLM_PROVIDER`` / ``DEEPSEEK_*`` 等旁路 env——模型来源单点化，
避免「同一模型两处声明、行为不一致」。

解析优先级：
  1. 显式 ModelConfig id（家长自定义，需 parent_id + session，越权返回 None）
  2. 未指定 model_ref 时，回落本家长的默认 ModelConfig（模型管理「设为默认」）
  3. 均无 → 返回 None，由上层下发「未配置模型」提示（无离线 mock 兜底）。

本模块只做**配置解析**（读 ModelConfig 表 / 解密密钥 → 中性参数），
真正的 Genkit 实例构造在 ``agent_core.adapters.genkit.build_genkit_engine``
（全工程唯一 ``import genkit`` 处）——app 层不再直接依赖 genkit SDK。
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Any

from sqlmodel import Session, select

from agent_core.adapters.genkit import build_genkit_engine
from app.core.config import settings
from app.core.crypto import decrypt
from app.db.models import ModelConfig


@dataclass
class EngineResolution:
    genkit: Any  # Genkit 实例（由 agent_core 适配器构造；本层不 import genkit）
    model: str  # 形如 ollama/llama3 或 openai/gpt-4o-mini
    # 是否具备原生思维链（DeepSeek-R1 / o-series / QwQ 等）：为真时出题流可读取
    # 提供方的思维链 token 发 REASONING 增量（ADR-0017 升级路径）；否则走单次调用
    # + 结构化 reasoning 字段打底，由前端打字机揭示。
    supports_reasoning: bool = False


# 原生思维链模型的名称启发式（小写子串匹配）。新增模型时在此补充。
_REASONING_HINTS = (
    "reason",
    "r1",
    "o1",
    "o3",
    "qwq",
    "deepseek-reasoner",
    "thinking",
)


def _supports_reasoning(model_name: str) -> bool:
    n = (model_name or "").lower()
    return any(hint in n for hint in _REASONING_HINTS)


def _as_uuid(value: object) -> uuid.UUID | None:
    """仅当 model_ref 是合法 UUID 时才查 ModelConfig 表。

    ModelConfig 主键为 uuid.UUID，把非 UUID 字符串直接交给 ``session.get`` 会让
    UUID 类型的 bind 处理器对字符串调 ``.hex`` 而崩溃。非法引用一律当作「查不到」。
    """
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError, AttributeError):
        return None


def _get_or_build(
    provider: str,
    base_url: str | None,
    api_key: str | None,
    model_name: str,
) -> EngineResolution:
    """把中性参数交给适配器工厂构造引擎（构造与缓存都在 ``agent_core`` 适配器内）。"""
    if provider == "ollama":
        base_url = base_url or settings.OLLAMA_BASE_URL
    engine = build_genkit_engine(
        provider=provider,
        model_name=model_name,
        base_url=base_url,
        api_key=api_key,
    )
    return EngineResolution(
        genkit=engine.genkit,
        model=engine.model,
        supports_reasoning=_supports_reasoning(model_name),
    )


def resolve_engine(
    model_ref: str | None = None,
    *,
    parent_id: object | None = None,
    session: Session | None = None,
) -> EngineResolution | None:
    """解析模型引用 → 引擎；未配置「模型管理」中的模型时返回 None。

    优先级（唯一配置源是「模型管理」，不再读本地 LLM_PROVIDER 等 env，也没有内置目录）：
      1. 显式 ModelConfig id（家长自定义，需 parent_id + session，越权返回 None）
      2. 未指定 model_ref 时，回落本家长的默认 ModelConfig（模型管理「设为默认」）
      3. 均无 → 返回 None，由上层下发「未配置模型」提示（无离线 mock 兜底，需经「模型管理」配置真实模型）

    显式引用查不到时**不回落默认模型**——避免静默用错引擎答出别家的题。
    """
    # 1) 家长自定义 ModelConfig（仅 model_ref 为合法 UUID 时才查表）
    if model_ref and session is not None and parent_id is not None:
        mc_id = _as_uuid(model_ref)
        if mc_id is not None:
            mc = session.get(ModelConfig, mc_id)
            if mc is not None and str(mc.parent_id) == str(parent_id):
                api_key = decrypt(mc.api_key_enc) if mc.api_key_enc else None
                return _get_or_build(mc.provider, mc.base_url, api_key, mc.model_name)

    # 2) 未指定模型 → 回落本家长在「模型管理」中设为默认的 ModelConfig
    if model_ref is None and session is not None and parent_id is not None:
        mc = _default_model_config(session, parent_id)
        if mc is not None:
            api_key = decrypt(mc.api_key_enc) if mc.api_key_enc else None
            return _get_or_build(mc.provider, mc.base_url, api_key, mc.model_name)

    # 3) 无可用模型（未配置）→ None
    return None


def _default_model_config(session: Session, parent_id: object) -> ModelConfig | None:
    """查本家长的默认 ModelConfig（模型管理「设为默认」）。"""
    try:
        pid = uuid.UUID(str(parent_id))
    except (ValueError, TypeError, AttributeError):
        return None
    return session.exec(
        select(ModelConfig).where(
            ModelConfig.parent_id == pid, ModelConfig.is_default.is_(True)
        )
    ).first()
