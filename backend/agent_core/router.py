"""agent_core 意图路由（业务无关：规则优先 + 启发式兜底 + 可切换 LLM 兜底）。

两级路由：
1. **规则匹配**：按 ``priority`` 降序逐个匹配可见 subagent 清单里的 ``triggers``，命中即路由。
2. **启发式兜底**：规则全未命中时匹配 ``hints``；再不中则落到 ``priority`` 最低的业务。

弱意图的 LLM 兜底（``agent_core.adapters.llm_route.classify_llm``）作为**可切换的第三类
路由原语**存在，由 ``runtime.decide`` 的策略开关（``AI_ROUTING_STRATEGY``）决定是否启用
——默认不启用，确定性优先，契合儿童产品等对路由确定性有要求的场景。它与决策模型
（Laya-multilingual）同属「按上下文 + 能力清单选业务」的原语，可互相切换，规则 ``classify``
恒为最终兜底。

本模块是内核（不含 ``adapters/``），仅依赖 stdlib + 自身；LLM 分类所需的 ``sqlmodel``
schema 落在其适配器模块，避免内核引入第三方依赖（见 ``tests/ai/test_layering_invariants``）。
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


@dataclass(frozen=True)
class Classification:
    """``classify`` 的结构化结果（ADR-0098）。

    - ``business``：路由目标。
    - ``trigger``：规则匹配命中的触发词；启发式 / 兜底 / 无可用清单时为 ``None``。
      业务合并后（如 question 并入 tasks），调用方靠命中词子公司意图——出题槽位
      预检按「词落在哪个 intent 组」选 schema，无需第二套匹配器。
    - ``level``：决策层级（``rule`` / ``heuristic`` / ``fallback``），供测试断言
      路由走了哪一级，重排词表时不碎。
    """

    business: str
    trigger: str | None = None
    level: str = "fallback"


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
) -> tuple[str, str] | None:
    """规则匹配：返回 ``(business, 命中触发词)``；未命中返回 ``None``。

    命中词随结果返回（ADR-0098）：业务合并后调用方需要它分子意图（如出题槽位
    预检按命中词落在哪个 intent 组选 schema）。词表遍历顺序即优先级语义，
    与原先只返回 business 时完全一致。

    两级：先字面触发词（子串），再正则触发词（``trigger_patterns``）。
    **两级都按 business 优先级排序**，所以正则不会抢在该业务自己的高优字面词
    前面，也不会跨业务抢先——某个业务的正则命中词仍按该业务的位置排序。

    为什么要正则（ADR-0101）：字面词是**子串**匹配，「出几道」命不中「出 2 道」
    （数字一变就漏），而用户写「出2道 / 出一道 / 来三题」远比写「出几道」多。
    """
    low = _norm(text)
    for biz in _ordered(businesses, manifests):
        for trig in manifests[biz].triggers:
            if _norm(trig) in low:
                return biz, trig
    for biz in _ordered(businesses, manifests):
        for pattern, trigger in manifests[biz].trigger_patterns:
            if pattern.search(low):
                return biz, trigger
    return None


def _heuristic(
    text: str, businesses: Sequence[str], manifests: dict[str, SubAgentManifest]
) -> tuple[str, str]:
    """启发式兜底：返回 ``(business, level)``——``heuristic``（hint 命中）或
    ``fallback``（priority 最低业务 / tutor）。"""
    low = _norm(text)
    ordered = _ordered(businesses, manifests)
    for biz in ordered:
        for hint in manifests[biz].hints:
            if _norm(hint) in low:
                return biz, "heuristic"
    # 兜底：priority 最低的业务
    return (ordered[-1] if ordered else "tutor"), "fallback"


async def classify(
    text: str,
    *,
    available: Sequence[str],
    manifests: dict[str, SubAgentManifest],
) -> Classification:
    """把自由文本路由到某个可见 business。链路：规则 → 启发式。"""
    if not available:
        return Classification(business="tutor", level="fallback")

    ruled = _rule_match(text, available, manifests)
    if ruled is not None:
        biz, trig = ruled
        return Classification(business=biz, trigger=trig, level="rule")

    biz, level = _heuristic(text, available, manifests)
    return Classification(business=biz, level=level)


# ───────────────────────── 路由上下文 / 能力清单共享辅助（内核，stdlib-only） ─────────────────────────
# 决策模型（Laya，适配器）与 LLM 分类（adapters/llm_route，适配器）共用：把「近期历史 +
# 当前消息」拼成模型可读的 state，把 manifest 的 name/description/actions 拼成能力选项。
# 放内核是因为两者都依赖它，而它本身只用到 stdlib，不破坏内核零第三方依赖约束。
ROUTING_HISTORY_LIMIT = 12  # 近期轮次足够消歧（Laya-multilingual 上下文 1024 tok）


def _build_routing_state(history: "list[dict] | None", text: str) -> str:
    """把「近期历史 + 当前消息」拼成路由模型的 ``state`` 文本。

    实现「每轮保持所有消息上下文」：续接时 history 为既有轮次，当前消息追尾，
    使模型在上下文里区分「补参数（留 tasks）」与「作答（交 tutor）」，无需黏性分支。
    """
    parts: list[str] = []
    if history:
        for turn in history[-ROUTING_HISTORY_LIMIT:]:
            if not isinstance(turn, dict):
                continue
            role = turn.get("role")
            content = turn.get("content")
            if content:
                parts.append(f"{role or 'user'}: {content}")
    if text:
        parts.append(f"user: {text}")
    return "\n".join(parts)


def _capability_text(manifest: SubAgentManifest) -> str:
    """把 manifest 的 ``name`` / ``description`` / ``actions`` 拼成能力描述。

    即「按 agent 能力路由」的能力清单：新增 subagent 自动扩展候选，无需改路由代码。
    """
    bits = [manifest.name]
    if manifest.description:
        bits.append(manifest.description)
    if manifest.actions:
        bits.append("actions: " + ", ".join(manifest.actions))
    return "\n".join(bits)

