"""SubAgent 注册表（ADR-0021 / 0024 / ADR-0030 发现即注册）。

ADR-0030 之前这里维护一张手工登记表（新增业务要在此加一行），与「文件夹发现」并存，
形成两处真相——漏登记会静默回退到 tutor。现在本模块只保留「业务键 → 类」的查询入口，
实现改为**基于 ``discover_subagent_manifests()`` 的发现结果**（清单里带 ``agent_cls``），
新增 subagent 只需丢一个文件夹，无需改动本文件。

``AgentRuntime`` 直接从自己持有的清单取 ``agent_cls`` 实例化；本模块供测试与
runtime 之外的调用方使用（结果按进程缓存，与 AgentRuntime 单例的发现一致）。
"""
from __future__ import annotations

from app.ai.runtime.manifest import discover_subagent_manifests
from app.ai.subagents.base import BaseSubAgent

_CACHE: dict[str, type[BaseSubAgent]] | None = None


def _load() -> dict[str, type[BaseSubAgent]]:
    global _CACHE
    if _CACHE is None:
        _CACHE = {
            business: manifest.agent_cls
            for business, manifest in discover_subagent_manifests().items()
            if manifest.agent_cls is not None
        }
    return _CACHE


def get_subagent_class(business: str) -> type[BaseSubAgent] | None:
    """业务键 → SubAgent 类；未知业务返回 None（调用方决定兜底）。"""
    return _load().get(business)


def build_subagent(
    business: str, *, provider, retriever=None
) -> BaseSubAgent | None:
    """业务键 → SubAgent 实例；未知业务返回 None（调用方决定兜底）。

    ADR-0030：不再接受 ``engine``——引擎统一由 ``AgentRuntime`` 解析后经
    ``build_provider(engine=...)`` 注入 provider，SubAgent 只从 provider 取。
    """
    agent_cls = get_subagent_class(business)
    if agent_cls is None:
        return None
    return agent_cls(provider=provider, retriever=retriever)


__all__ = [
    "get_subagent_class",
    "build_subagent",
]
