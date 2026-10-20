"""agent_core Agent Runtime（业务无关的统一编排）。

职责：
1. 文件夹发现：扫描 subagent 文件夹加载 manifest（业务键/可见角色/触发词/skills）。
2. 意图路由：动作直配 → 策略原语（决策模型 / LLM 分类），规则（关键词/启发式）路由已移除。
3. 角色感知：按当前 role 过滤可见 subagent。
4. 事件流：调用 SubAgent.run / run_with_tools 产出 AG-UI 事件帧，由端点以 SSE 推送。
5. 真实 tool loop：SubAgent 声明 tools 时，runtime 以「选型→执行→回灌→循环」调度。

本模块**零业务依赖**：模型/检索/安全均为注入的抽象 seam（RuntimeDeps），不 import 任何
app.* 符号。会话持久化交给端点（复用业务自身的会话表）。
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, AsyncIterator

from agent_core.adapters.llm_route import classify_llm
from agent_core.errors import ProviderRequestError
from agent_core.ports import DecisionOption, RuntimeDeps
from agent_core.protocol import (
    AssistantEvent,
    done,
    error,
    run_started,
    thinking,
    user_message,
)
from agent_core.registry import (
    SubAgentManifest,
    build_subagent,
    discover_subagent_manifests,
)
from agent_core.router import (
    IntentSignal,
    _build_routing_state,
    _capability_text,
    match_action,
)
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools


@dataclass
class RouteDecision:
    """一次路由的结构化决策，由 ``run``/``decide`` 显式返回供端点消费。

    - ``business``：路由到的业务键；``None`` 表示输入被安全闸门拦截（不路由）。
    - ``name``：业务可读名（来自 manifest.name）。
    - ``extra``：路由附加信息（如置信度、``routed_by``），业务无关。

    ADR-0104：规则（关键词/启发式）路由移除后不再有 ``trigger`` 子意图词——
    出题引导（必填槽澄清 + 规格回显）随规则一并下线，聊天链路走纯 LLM 生成。
    """

    business: str | None
    name: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)


# ───────────────────────── 路由策略（可切换：llm / decision / auto） ─────────────────────────
# 默认 ``auto``＝决策模型若可用则用之、否则通用 LLM 分类（``AI_ROUTING_STRATEGY=llm``）。
# 规则（关键词/启发式）路由已移除：业务选择完全由模型按上下文 + 能力清单决定。
# 策略原语均不可用 / 不置信时，回落到「无命中引导」——声明了 ``fallback_guide`` 的业务
# （生产拓扑即能力自述 capability，ADR-0105），提示用户助手能做什么； tutor 等执行体
# 必须被模型显式路由到，不再作兜底，保证路由永不返回 ``None``（安全闸门拦截除外）。
_ROUTING_STRATEGY_OVERRIDE: str | None = None

_STRATEGY_ORDER: dict[str, list[str]] = {
    "llm": ["llm"],
    "decision": ["decision", "llm"],
    "auto": ["decision", "llm"],
}


def set_routing_strategy(strategy: str | None) -> None:
    """覆盖路由策略（测试 / 运行时配置用）。``None`` 复位为环境变量值。"""
    global _ROUTING_STRATEGY_OVERRIDE
    _ROUTING_STRATEGY_OVERRIDE = (strategy or "").strip().lower() or None


def get_routing_strategy() -> str:
    """当前路由策略：覆盖值优先，否则环境变量 ``AI_ROUTING_STRATEGY``，默认 ``auto``。"""
    raw = _ROUTING_STRATEGY_OVERRIDE or os.getenv("AI_ROUTING_STRATEGY", "auto")
    return (raw or "auto").strip().lower()


class AgentRuntime:
    def __init__(self, manifests: dict[str, SubAgentManifest]) -> None:
        self._manifests = manifests

    @property
    def manifests(self) -> dict[str, SubAgentManifest]:
        """已发现的 subagent 清单（业务键 → 清单），只读视图。"""
        return self._manifests

    # ── 发现 ──
    @classmethod
    def discover(
        cls, root: Path | None = None, *, module_base: str = "app.ai.subagents"
    ) -> "AgentRuntime":
        return cls(discover_subagent_manifests(root, module_base=module_base))

    # ── 角色可见性 ──
    def visible_businesses(self, role: str) -> list[str]:
        """按当前角色过滤可见 subagent。"""
        return [b for b, m in self._manifests.items() if role in m.roles]

    def name_of(self, business: str) -> str:
        m = self._manifests.get(business)
        return m.name if m else business

    # ── 路由决策（纯计算，不流式、不构建依赖） ──
    async def decide(
        self,
        signal: "str | IntentSignal",
        *,
        role: str,
        deps: RuntimeDeps,
        history: "list[dict] | None" = None,
    ) -> RouteDecision:
        """解析路由决策：角色可见性 → 安全闸门 → 动作直配 → 策略原语 → 无命中引导。

        输入接受 ``str``（迁移期兼容）或 ``IntentSignal``；不产出事件帧、不构建 provider。
        端点可据此在流式前做预航班（配额判定）。

        路由分两级：动作直配恒在最前；其后的路由原语（决策模型 / 通用 LLM 分类）
        由策略开关 ``get_routing_strategy()``（环境变量 ``AI_ROUTING_STRATEGY``，默认
        ``auto``）选择，规则（关键词/启发式）路由已移除。

        1. **动作直配**（不变）：``signal.action`` 与各 manifest ``actions`` 等值匹配，
           命中即路由，不参与优先级排序、不与文本竞争（ADR-0081，不变）。
        2. **策略原语**（按 ``_STRATEGY_ORDER`` 顺序尝试，首个非空即返回）：
           - ``decision``：``deps.decision_model``（Laya-multilingual）可用时，以
             「近期 history + 当前消息」为 ``state``、能力清单为选项，返回「业务 + 校准概率」
             （``extra.routed_by = "decision"``）；不可用 / 不置信回落下一候选。
           - ``llm``：通用 LLM 结构化分类（``classify_llm``），history + 能力清单为上下文，
             返回业务键（``extra.routed_by = "llm"``）；provider 不可用 / 不守 schema 回落。

        ``history`` 让路由基于完整对话上下文（而非孤立当前句），天然实现「续接留住出题态」
        而无需手写黏性分支；也支撑「按 agent 能力路由」（manifest 的 ``description``/
        ``actions`` 即能力清单）。

        策略原语均不可用 / 不置信（都没有命中）时，回落到**无命中引导**：声明了
        ``fallback_guide`` 的业务（生产拓扑即能力自述 ``capability``，ADR-0105）接住并
        提示「自身能做什么」。执行体（tasks / tutor）必须被模型显式路由到，不再作兜底。
        本方法不产出子意图词（规则路由已移除，ADR-0104），出题引导链路随之走纯 LLM 生成。

        动作命中但业务对当前角色**不可见** → 返回显式 ``action_not_visible``，**禁止**沿用
        「换成第一个可见业务」的静默兜底（那会把越权变成答非所问）。未知动作 → 容错回落文本路由，
        不报错（动作名与清单不同步的静默失效由契约测试兜住）。
        """
        if isinstance(signal, str):
            signal = IntentSignal(text=signal)
        text = signal.text or ""

        visible = self.visible_businesses(role)

        # 输入安全（首层防御）：被拦截则不路由。
        if deps.safety is not None and not deps.safety.check_input(text).safe:
            return RouteDecision(business=None, name=None)

        # 第一级：结构化动作直配（等值匹配，不参与文本优先级竞争）。
        if signal.action:
            owner = match_action(signal.action, self._manifests)
            if owner is not None:
                if owner in visible:
                    return RouteDecision(
                        business=owner,
                        name=self.name_of(owner),
                        extra={"routed_by": "action", "action": signal.action},
                    )
                # 动作命中但当前角色不可见：显式不可见，禁止静默回落成答非所问。
                return RouteDecision(
                    business=None,
                    name=None,
                    extra={"reason": "action_not_visible", "action": signal.action},
                )
            # 未知动作：容错回落自然语言路由（不报错）；同名不同步的静默失效由契约测试兜。

        # 策略路由：按配置顺序尝试 决策模型 / LLM 分类。
        strategy = get_routing_strategy()
        order = _STRATEGY_ORDER.get(strategy, _STRATEGY_ORDER["auto"])
        for candidate in order:
            routed = await self._route_candidate(candidate, text, visible, deps, history)
            if routed is not None:
                return routed

        # 策略原语均未决策（都没有命中）：回落「无命中引导」——声明了 fallback_guide 的
        # 业务接住并提示自身能力（ADR-0105），而不是静默把消息塞给某个执行体。
        return self._fallback_decision(visible)

    # ── 路由候选（策略分发） ──
    async def _route_candidate(
        self,
        candidate: str,
        text: str,
        visible: list[str],
        deps: RuntimeDeps,
        history: "list[dict] | None",
    ) -> "RouteDecision | None":
        """按策略名尝试单个路由原语；返回 ``None`` 表示「本原语不决策」，由下一候选兜底。"""
        if candidate == "decision":
            return await self._route_decision(text, visible, deps, history)
        if candidate == "llm":
            return await self._route_llm(text, visible, deps, history)
        return None

    async def _route_decision(
        self,
        text: str,
        visible: list[str],
        deps: RuntimeDeps,
        history: "list[dict] | None",
    ) -> "RouteDecision | None":
        """决策模型（Laya-multilingual）主路由；不可用 / 低置信 / 不可见 → ``None`` 回落。"""
        dm = deps.decision_model
        if dm is None or not dm.available():
            return None
        state = _build_routing_state(history, text)
        options = [
            DecisionOption(key=biz, label=_capability_text(self._manifests[biz]))
            for biz in visible
        ]
        try:
            result = await dm.decide(state=state, options=options)
        except Exception:  # noqa: BLE001 — 决策模型异常不应击穿路由
            return None
        if result is not None and result.choice in visible:
            return RouteDecision(
                business=result.choice,
                name=self.name_of(result.choice),
                extra={
                    "routed_by": "decision",
                    "level": "decision",
                    "prob": result.prob,
                },
            )
        return None

    async def _route_llm(
        self,
        text: str,
        visible: list[str],
        deps: RuntimeDeps,
        history: "list[dict] | None",
    ) -> "RouteDecision | None":
        """通用 LLM 分类路由（结构化输出）；provider 不可用 / 不守 schema / 业务不可见 → ``None`` 回落。"""
        decision = await classify_llm(
            deps.provider, history, text, self._manifests, visible
        )
        if decision is None or decision.business not in visible:
            return None
        return RouteDecision(
            business=decision.business,
            name=self.name_of(decision.business),
            extra={
                "routed_by": "llm",
                "level": "llm",
                "confidence": decision.confidence,
            },
        )

    def _fallback_decision(self, visible: list[str]) -> RouteDecision:
        """策略原语均未决策时的无命中引导：声明 ``fallback_guide`` 的业务接住。

        ADR-0105：tutor 等执行体必须被模型显式路由到，不再作兜底；都没有命中时提示
        「自身能力引导」（生产拓扑即能力自述 capability）。保证路由永不返回 ``None``
        （安全闸门拦截的路径除外，由调用方处理）。
        """
        biz = self._fallback_business(visible)
        return RouteDecision(
            business=biz,
            name=self.name_of(biz) if biz else None,
            extra={"routed_by": "default", "level": "fallback"},
        )

    def _fallback_business(self, visible: list[str]) -> str | None:
        """无命中落点：可见集中声明了 ``fallback_guide`` 的业务（ADR-0105）。

        没有任何业务声明（或声明业务对当前角色不可见）时，退到可见集中 priority
        最小者作**最后防线**——当前生产拓扑不可达（capability 双端可见），仅为将来
        的清单变化保住「路由永不返回 None」。无可见集返回 ``None``。
        """
        if not visible:
            return None
        for biz in visible:
            if self._manifests[biz].fallback_guide:
                return biz
        return min(visible, key=lambda b: self._manifests[b].priority)

    # ── 运行 ──
    async def run(
        self,
        message: str,
        *,
        role: str,
        ctx: SubAgentContext,
        deps: RuntimeDeps,
        business: str | None = None,
        session: Any = None,
    ) -> AsyncIterator[AssistantEvent]:
        """产出统一事件流（AgentRuntime 不负责 SSE 推送，仅产出帧）。

        - 决策由 ``decide`` 计算（端点可预航班复用，避免重复路由）。
        - 依赖（provider/retriever）由 deps 注入；SubAgent 声明 tools 时走真实 tool loop。
        """
        if business is None:
            yield error("输入含不适当内容，已拒绝。", code="INPUT_UNSAFE")
            yield done(ctx.extra.get("session_id") if isinstance(ctx.extra.get("session_id"), str) else None)
            return

        name = self.name_of(business)
        yield run_started()
        yield user_message(message)
        yield thinking("正在理解你的需求，并选择最合适的助手…", extra={"routing": True})
        yield thinking(f"已选择助手：{name}", extra={"routing": True})

        agent: BaseSubAgent | None = build_subagent(
            self._manifests, business, provider=deps.provider, retriever=deps.retriever
        )
        if agent is None:
            yield error(f"未找到可用的助手：{business}", code="NO_AGENT")
            yield done(ctx.extra.get("session_id") if isinstance(ctx.extra.get("session_id"), str) else None)
            return

        # 把 manifest 声明的 SOP 注入 ctx（若 subagent 自身未带）。
        manifest = self._manifests.get(business)
        if not ctx.skills and manifest:
            ctx.skills = manifest.skill_prompt

        try:
            async for ev in run_with_tools(
                agent, message, ctx, session=session, hooks=deps.hooks
            ):
                yield ev
        except ProviderRequestError as exc:
            # 厂商拒绝请求（认证/限流/网络）：给可操作提示，别把 401 说成「助手执行出错」（ADR-0038）。
            yield error(exc.user_hint, code="PROVIDER_ERROR")
        except Exception as exc:  # noqa: BLE001 — 单 subagent 异常不应让整条流崩
            yield error(f"助手执行出错：{exc}", code="AGENT_ERROR")
        finally:
            yield done(ctx.extra.get("session_id") if isinstance(ctx.extra.get("session_id"), str) else None)
