"""意图路由（ADR-0024 规则优先，ADR-0030 去硬编码 + 删除未接线的 LLM 插槽）。

两级路由：
1. **规则匹配**：按 ``priority`` 降序逐个匹配可见 subagent 清单里的 ``triggers``，命中即路由。
2. **启发式兜底**：规则全未命中时匹配 ``hints``；再不中则落到 ``priority`` 最低的业务（当前 tutor）。

ADR-0030 的两处收敛：
- 业务名与词表**全部来自 manifest**（``priority`` / ``triggers`` / ``hints``），本模块不再认识
  任何具体业务，新增 subagent 无需改这里。
- **删除 ``llm_classify`` 插槽**：它从未被传参。三个业务的分类用规则 + 启发式已足够，
  接 LLM 会让每条请求多一次完整模型往返换一个三选一，且牺牲儿童产品的路由确定性。
  真要加回，只需给 ``classify`` 加一个 callable 参数（约 5 行）。
"""
from __future__ import annotations

from typing import Sequence

from app.ai.runtime.manifest import SubAgentManifest


def _norm(text: str) -> str:
    return (text or "").strip().lower()


def _ordered(businesses: Sequence[str], manifests: dict[str, SubAgentManifest]) -> list[str]:
    """按 priority 降序排列（同优先级按 business 字典序），保证匹配顺序确定。

    末位是 priority 最低者，即「规则与启发式都没命中」时的兜底业务。
    """
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
    # 兜底：priority 最低的业务（当前为 tutor）
    return ordered[-1] if ordered else "tutor"


async def classify(
    text: str,
    *,
    available: Sequence[str],
    manifests: dict[str, SubAgentManifest],
) -> str:
    """把自由文本路由到某个可见 business。链路：规则匹配 → 启发式兜底。"""
    if not available:
        return "tutor"

    ruled = _rule_match(text, available, manifests)
    if ruled is not None:
        return ruled

    return _heuristic(text, available, manifests)
