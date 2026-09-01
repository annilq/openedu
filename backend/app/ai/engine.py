"""Genkit 引擎解析（ADR-0015）：把「模型引用」解析为可用的 Genkit 实例 + model 字符串。

解析优先级：
  1. 显式 ModelConfig id（家长自定义，需 parent_id + session，越权返回 None）
  2. 内置模型 id（settings.BUILTIN_MODELS JSON）
  3. 全局 LLM_PROVIDER（deepseek / langchain）→ 对应端点
  mock 模式或无法解析 → 返回 None，由端点回退 MockProvider。

实例按 (provider, base_url, api_key, model_name) 缓存，避免重复构建。
genkit 仅在本文件 import。
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from typing import Any

from genkit import Genkit
from genkit_ollama import Ollama
from genkit_openai import OpenAI
from sqlmodel import Session

from app.core.config import settings
from app.core.crypto import decrypt
from app.models import ModelConfig

_ENGINE_CACHE: dict[tuple[str, str | None, str | None, str], Genkit] = {}


@dataclass
class EngineResolution:
    genkit: Genkit
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


def _prefix(provider: str) -> str:
    return "ollama" if provider == "ollama" else "openai"


def _as_uuid(value: object) -> uuid.UUID | None:
    """仅当 model_ref 是合法 UUID 时才查 ModelConfig 表。

    ModelConfig 主键为 uuid.UUID，直接把内置 id（如 'local-llama'）传给
    session.get 会让 UUID 类型的 bind 处理器对字符串调 .hex 而崩溃。
    """
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError, AttributeError):
        return None


def _builtin_models() -> list[dict[str, Any]]:
    try:
        return json.loads(settings.BUILTIN_MODELS) or []
    except (json.JSONDecodeError, ValueError):
        return []


def list_builtin_models() -> list[dict[str, Any]]:
    """管理员内置模型清单（GET /models 使用，无需登录/家长归属）。"""
    return _builtin_models()


def _get_or_build(
    provider: str,
    base_url: str | None,
    api_key: str | None,
    model_name: str,
) -> EngineResolution:
    key = (provider, base_url, api_key, model_name)
    cached = _ENGINE_CACHE.get(key)
    if cached is not None:
        return EngineResolution(
            genkit=cached,
            model=f"{_prefix(provider)}/{model_name}",
            supports_reasoning=_supports_reasoning(model_name),
        )
    if provider == "ollama":
        ai = Genkit(
            plugins=[Ollama(server_address=base_url or settings.OLLAMA_BASE_URL)],
            model=f"ollama/{model_name}",
        )
    else:  # openai_compat
        ai = Genkit(
            plugins=[OpenAI(api_key=api_key or "none", base_url=base_url)],
            model=f"openai/{model_name}",
        )
    _ENGINE_CACHE[key] = ai
    return EngineResolution(
        genkit=ai,
        model=f"{_prefix(provider)}/{model_name}",
        supports_reasoning=_supports_reasoning(model_name),
    )


def resolve_engine(
    model_ref: str | None = None,
    *,
    parent_id: object | None = None,
    session: Session | None = None,
) -> EngineResolution | None:
    """解析模型引用 → Genkit 引擎；mock/不可解析返回 None。"""
    # 1) 家长自定义 ModelConfig（仅 model_ref 为合法 UUID 时才查表，避免内置 id 触发 .hex 崩溃）
    if model_ref and session is not None and parent_id is not None:
        mc_id = _as_uuid(model_ref)
        if mc_id is not None:
            mc = session.get(ModelConfig, mc_id)
            if mc is not None and str(mc.parent_id) == str(parent_id):
                api_key = decrypt(mc.api_key_enc) if mc.api_key_enc else None
                return _get_or_build(mc.provider, mc.base_url, api_key, mc.model_name)

    # 2) 内置模型 id
    if model_ref:
        for m in _builtin_models():
            if m.get("id") == model_ref:
                return _get_or_build(
                    m.get("provider", "openai_compat"),
                    m.get("base_url"),
                    m.get("api_key"),
                    m["model_name"],
                )

    # 3) 全局 LLM_PROVIDER
    provider = settings.LLM_PROVIDER
    if provider == "deepseek":
        return _get_or_build(
            "openai_compat", settings.DEEPSEEK_BASE_URL, settings.DEEPSEEK_API_KEY, settings.DEEPSEEK_MODEL
        )
    if provider == "langchain":
        if not settings.LLM_BASE_URL or not settings.LLM_MODEL:
            return None
        return _get_or_build(
            "openai_compat", settings.LLM_BASE_URL, settings.LLM_API_KEY or None, settings.LLM_MODEL
        )
    # mock 或未知 → 无真实引擎（端点回退 MockProvider）
    return None
