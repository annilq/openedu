"""agent_core 意图路由（业务无关：规则优先 + 启发式兜底 + 可插拔 LLM 分类）。

两级路由：
1. **规则匹配**：按 ``priority`` 降序逐个匹配可见 subagent 清单里的 ``triggers``，命中即路由。
2. **启发式兜底**：规则全未命中时匹配 ``hints``；再不中则落到 ``priority`` 最低的业务。

本模块不认识任何具体业务；业务名与词表全部来自 manifest。弱意图领域可传入
``llm_classify(callable)`` 做最终兜底（约 5 行接线），默认走规则 + 启发式（确定性优先，
契合儿童产品等对路由确定性有要求的场景）。
"""
from __future__ import annotations

from typing import Callable, Sequence

from agent_core.registry import SubAgentManifest


def _norm(text: str) -> str:
    return (text or "").strip().lower()


def _ordered(businesses: Sequence[str], manifests: dict[str, SubAgentManifest]) -> list[str]:
    """按 priority 降序排列（同优先级按 business 字典序），保证匹配顺序确定。"""
    return sorted(
        (b for b in businesses if b in manifests),
        key=lambda b: (-manifests[b].priority, b),
    )


def _rule_match(
    text: str, businesses: Sequence[str], manifests: dict[str, SubAgentManifest]
) -> str | None:
    low = _norm(text)
    for biz in _ordered(businesses, manifests):
        for trig in manifests[biz].triggers:
            if _norm(trig) in low:
                return biz
    return None


def _heuristic(
    text: str, businesses: Sequence[str], manifests: dict[str, SubAgentManifest]
) -> str:
    low = _norm(text)
    ordered = _ordered(businesses, manifests)
    for biz in ordered:
        for hint in manifests[biz].hints:
            if _norm(hint) in low:
                return biz
    # 兜底：priority 最低的业务
    return ordered[-1] if ordered else "tutor"


async def classify(
    text: str,
    *,
    available: Sequence[str],
    manifests: dict[str, SubAgentManifest],
    llm_classify: Callable[[str, list[str]], str] | None = None,
) -> str:
    """把自由文本路由到某个可见 business。链路：规则 → 启发式 →（可选）LLM 兜底。"""
    if not available:
        return "tutor"

    ruled = _rule_match(text, available, manifests)
    if ruled is not None:
        return ruled

    return _heuristic(text, available, manifests)
