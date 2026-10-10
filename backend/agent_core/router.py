"""agent_core 意图路由（业务无关：规则优先 + 启发式兜底）。

两级路由：
1. **规则匹配**：按 ``priority`` 降序逐个匹配可见 subagent 清单里的 ``triggers``，命中即路由。
2. **启发式兜底**：规则全未命中时匹配 ``hints``；再不中则落到 ``priority`` 最低的业务。

本模块不认识任何具体业务；业务名与词表全部来自 manifest。链路到此为止：没有第三级
（弱意图的 LLM 兜底另立扩展点，且须显式配置后才生效），确定性优先，契合儿童产品等对
路由确定性有要求的场景。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Sequence

from agent_core.registry import SubAgentManifest


@dataclass(frozen=True)
class IntentSignal:
    """路由输入从「一段文本」升级为「结构化意图信号」。

    - ``text``：用户原始输入；结构化请求（如按规格出题）可为空串。
    - ``action``：结构化动作键（如 ``task_generate``），与各 manifest ``actions`` 做
      **等值**匹配，命中即路由。它排在触发词匹配之前、且**不参与**优先级排序——
      因此不存在「谁的词更长 / 谁的 priority 更高」，也就没有竞争。``None`` 表示纯文本路由。
    - ``context``：结构化上下文（课件 / 待判定态等），透传给 SubAgent，不参与路由判定。
    """

    text: str = ""
    action: str | None = None
    context: dict[str, Any] | None = None

    @classmethod
    def from_text(cls, text: str) -> "IntentSignal":
        return cls(text=text)


def _norm(text: str) -> str:
    return (text or "").strip().lower()


def match_action(action: str, manifests: dict[str, SubAgentManifest]) -> str | None:
    """动作直配：动作键与各 manifest ``actions`` **等值**匹配，返回归属 business（唯一）。

    在所有 manifest 上匹配（不只可见集），以便 ``decide`` 区分「命中但不可见」与「未知动作」。
    遍历按 business 字典序固定，结果对清单顺序不敏感（唯一性由契约测试保证）。
    """
    norm = (action or "").strip()
    if not norm:
        return None
    for biz in sorted(manifests):
        if norm in manifests[biz].actions:
            return biz
    return None


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
) -> str:
    """把自由文本路由到某个可见 business。链路：规则 → 启发式。"""
    if not available:
        return "tutor"

    ruled = _rule_match(text, available, manifests)
    if ruled is not None:
        return ruled

    return _heuristic(text, available, manifests)
