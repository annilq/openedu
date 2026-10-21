"""通用 LLM 路由分类适配器（agent_core 第一方适配器，与 laya / genkit 平级）。

把「给定对话上下文 + 候选业务能力清单 → 选一个业务键」作为路由原语，复用通用 LLM 的
结构化输出（``LLMProvider.stream(schema=)``）。与决策模型（Laya-multilingual）互为
**可切换**的路由原语，由 ``runtime.decide`` 的策略开关（``AI_ROUTING_STRATEGY``）
决定是否启用——默认不启用（``auto`` 不进 LLM），确定性优先。

本模块落在 ``adapters/``：``RoutingDecision`` 是 ``sqlmodel`` schema，内核（``router``
等）不得引入第三方依赖，故 SQLModel 只出现在此适配器内（见
``tests/ai/test_layering_invariants`` 不变量 2）。
"""
from __future__ import annotations

from typing import Any, Sequence

from sqlmodel import SQLModel

from agent_core.ports import StructuredDone
from agent_core.registry import SubAgentManifest
from agent_core.router import _build_routing_state, _capability_text


class RoutingDecision(SQLModel):
    """通用 LLM 路由分类器的结构化产出（``classify_llm`` 的 schema）。

    - ``business``：选中的业务键（如 ``"tasks"``）；``classify_llm`` 会把它解析 /
      容错成可见集内的 key。
    - ``reason``：模型给出的简短理由（仅调试 / 轨迹用，不进正文）。
    - ``confidence``：模型**自报**置信度（0~1）；``None`` 表示模型没填。

    ``confidence`` 可空是有实测依据的（ADR-0107 / ticket 13）：44 条中文用例里
    deepseek 有 13 条没给这个字段；若按 ``0.0`` 参与 0.5 门控，会连带挡掉 6 条
    **正确**的路由（正确条数 36 → 30）。故 ``None`` 的语义是「未自报」而非「零置信」，
    runtime 见到 ``None`` 时不拿它去比门槛；给了值的那些仍与决策模型走同一张门控表。
    """

    business: str
    reason: str = ""
    confidence: "float | None" = None


# ADR-0104：路由规则整体移除，不再根据 if/elif 式规则分类路由。本提示词只描述
# 「按能力清单 + 上下文选业务键」的角色与输出格式，不内嵌任何编号路由规则。
# 能力清单与近期对话上下文由 build_routing_prompt 注入用户消息；此处仅保留角色
# 说明与「只输出业务键」的格式约束。
ROUTING_SYSTEM_PROMPT = (
    "你是教育助手的路由分类器。根据下方提供的「可用助手清单（业务键 — 名称 — "
    "描述 — 动作）」与「对话上下文」，判断用户最新消息应由哪个助手处理。\n"
    "只输出业务键的原文（如 tasks / tutor），不得翻译、改写或附加解释。"
)


def build_routing_prompt(*, catalog: str, state: str) -> str:
    """组装用户消息：能力清单 + 近期对话上下文。"""
    return (
        f"{catalog}\n\n"
        f"对话上下文（最近在前）：\n{state}\n\n"
        "请判断：用户最新消息应由哪个助手（业务键）处理？只输出业务键。"
    )


async def classify_llm(
    provider: Any,
    history: "list[dict] | None",
    message: str,
    manifests: dict[str, SubAgentManifest],
    visible: Sequence[str],
) -> "RoutingDecision | None":
    """用通用 LLM（结构化输出）做意图路由，返回 :class:`RoutingDecision` 或 ``None``。

    与决策模型（Laya）互为可切换的路由原语；``history`` 实现「每轮保持所有消息上下文」，
    ``manifests`` 的能力清单即候选。以下一律 ``None``（调用方据此回落兜底助手）：

    - provider 未配置 / 抛错 / 模型没给结构化产出 / 产出畸形；
    - 模型回传的业务既不在可见集、也匹配不上任何 manifest 的 name（含幻觉）。

    本函数**不**更改 ``provider`` 的聊天上下文，只复用其 ``stream(schema=)`` 原语。
    """
    if provider is None or not getattr(provider, "configured", True):
        return None
    if not visible:
        return None
    catalog = "\n".join(
        f"{biz} — {_capability_text(manifests[biz])}" for biz in visible
    )
    state = _build_routing_state(history, message)
    prompt = build_routing_prompt(catalog=catalog, state=state)
    try:
        async for ev in provider.stream(
            ROUTING_SYSTEM_PROMPT, prompt, schema=RoutingDecision
        ):
            if isinstance(ev, StructuredDone):
                return _coerce_routing(ev.data, manifests=manifests, visible=visible)
    except Exception:  # noqa: BLE001 — 路由 LLM 失败不应击穿主链路
        return None
    return None


def _coerce_routing(
    data: Any,
    *,
    manifests: dict[str, SubAgentManifest],
    visible: Sequence[str],
) -> "RoutingDecision | None":
    """结构化产出 → :class:`RoutingDecision`；并容错把 manifest name 解析成业务键。

    畸形（非 dict / 字段不符）→ ``None``；业务不在可见集且匹配不上 name → ``None``。
    """
    if isinstance(data, RoutingDecision):
        rd = data
    elif isinstance(data, dict):
        try:
            rd = RoutingDecision.model_validate(data)
        except Exception:  # noqa: BLE001 — 模型偶发不守 schema 属正常输入，不抛错
            return None
    else:
        return None
    biz = (rd.business or "").strip()
    if biz in visible:
        return rd
    # 容错：模型可能回传 manifest 的 name 而非业务键
    for b in visible:
        if manifests[b].name == biz:
            return RoutingDecision(
                business=b, reason=rd.reason, confidence=rd.confidence
            )
    return None


__all__ = [
    "RoutingDecision",
    "ROUTING_SYSTEM_PROMPT",
    "build_routing_prompt",
    "classify_llm",
]
