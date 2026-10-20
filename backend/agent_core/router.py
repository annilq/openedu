"""agent_core 意图路由（业务无关：动作直配 + 可切换 LLM/决策模型路由）。

两级路由：
1. **动作直配**：``IntentSignal.action`` 与各 manifest ``actions`` 等值匹配，命中即路由
   （ADR-0081），不参与文本优先级竞争。
2. **按上下文 + 能力清单选业务**：决策模型（Laya-multilingual）与通用 LLM 分类
   （``agent_core.adapters.llm_route.classify_llm``）作为可切换的路由原语，由
   ``runtime.decide`` 的策略开关（``AI_ROUTING_STRATEGY``）选择——默认 ``auto``
   ＝决策模型 → LLM 分类。规则（关键词 / 启发式）路由已移除：业务选择完全由模型按
   「对话上下文 + manifest 能力清单」决定，不再有手写关键词分支（见 T08 收尾）。

本模块是内核（不含 ``adapters/``），仅依赖 stdlib + 自身。``_build_routing_state`` /
``_capability_text`` 供决策模型与 LLM 分类复用，它们本身只用到 stdlib，不破坏内核
零第三方依赖约束（见 ``tests/ai/test_layering_invariants``）。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

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
