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
from agent_core.errors import ProviderRequestError, UnverifiedAnswerError
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
from agent_core.subagent import (
    UNVERIFIED_ANSWER_HINT,
    BaseSubAgent,
    SubAgentContext,
    run_with_tools,
)


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
# 每个原语是否**采纳**由 ``min_adopt_score`` 门控决定（ADR-0107），门控不通过的候选
# 记进 ``extra["rejected"]``。策略原语均不可用 / 未过门控时，回落到「无命中引导」——
# 声明了 ``fallback_guide`` 的业务
# （生产拓扑即能力自述 capability，ADR-0105），提示用户助手能做什么； tutor 等执行体
# 必须被模型显式路由到，不再作兜底，保证路由永不返回 ``None``（安全闸门拦截除外）。
_ROUTING_STRATEGY_OVERRIDE: str | None = None

_STRATEGY_ORDER: dict[str, list[str]] = {
    "llm": ["llm"],
    "decision": ["decision", "llm"],
    "auto": ["decision", "llm"],
    # 交叉校验（ADR-0107，ticket 13）：两个原语都跑，业务一致且各自过门控才采纳。
    # **不进默认**——它给每轮消息多加一次 LLM 往返，与「每轮同步路由」的延迟预算
    # 冲突，故只作显式可选档位。
    "consensus": ["consensus"],
}


def set_routing_strategy(strategy: str | None) -> None:
    """覆盖路由策略（测试 / 运行时配置用）。``None`` 复位为环境变量值。"""
    global _ROUTING_STRATEGY_OVERRIDE
    _ROUTING_STRATEGY_OVERRIDE = (strategy or "").strip().lower() or None


def get_routing_strategy() -> str:
    """当前路由策略：覆盖值优先，否则环境变量 ``AI_ROUTING_STRATEGY``，默认 ``auto``。"""
    raw = _ROUTING_STRATEGY_OVERRIDE or os.getenv("AI_ROUTING_STRATEGY", "auto")
    return (raw or "auto").strip().lower()


# ───────────────────────── 路由采纳门控（ADR-0107）─────────────────────────
# 决策模型 / LLM 分类只负责「给出候选 + 分数」；**是否采纳由 runtime 决定**。此前
# 阈值是 ``LayaDecisionModel(threshold=0.5)`` 的构造参数，运行时无从按角色 / 按业务
# 调整，且「不置信」与「没决策」被压成同一个 ``None``。上移后门控是一张**声明式**表：
#
#     min_adopt_score(business, role) = 业务自述覆盖 → 角色覆盖 → 全局默认
#
# 延续 ADR-0105 的 ``fallback_guide`` 纪律：内核只认「这个业务声明了更高门槛」这个
# 事实（manifest.min_adopt_score），不认任何业务键字面量。
DEFAULT_MIN_ADOPT_SCORE = 0.5

# 角色覆盖表。**当前为空是有实测依据的，不是没做完**（ticket 13 / eval 阈值扫描）：
# 学生端正确路由的 pmax 反而更低（0.41–0.76），抬门槛先掉的是正确路由；唯一一条
# 学生端有害错（0.702）要 ≥0.75 才挡得住，那会连带挡掉 10 条正确路由。故不设值。
_ROLE_MIN_ADOPT_SCORE: dict[str, float] = {}


def set_role_min_adopt_score(role: str, score: "float | None") -> None:
    """设置 / 清除某角色的采纳门槛覆盖（``None`` 清除）；测试与运行时配置用。"""
    if score is None:
        _ROLE_MIN_ADOPT_SCORE.pop(role, None)
    else:
        _ROLE_MIN_ADOPT_SCORE[role] = float(score)


def get_role_min_adopt_score(role: str) -> "float | None":
    """某角色的采纳门槛覆盖；未覆盖返回 ``None``（即走全局默认）。"""
    return _ROLE_MIN_ADOPT_SCORE.get(role)


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
             「近期 history + 当前消息」为 ``state``、能力清单为选项，返回「业务 + 分数」
             （``extra.routed_by = "decision"``）；不可用回落下一候选。
           - ``llm``：通用 LLM 结构化分类（``classify_llm``），history + 能力清单为上下文，
             返回业务键（``extra.routed_by = "llm"``）；provider 不可用 / 不守 schema 回落。
           - ``consensus``**（可选，非默认）**：上述两个原语都跑，业务一致才采纳
             （``extra.routed_by = "consensus"``）；多一次 LLM 往返，故不进默认策略。

        每个原语给不出「采纳级」的候选时返回 ``None``，由下一候选接住。**采纳与否由
        门控决定**（ADR-0107）：``分数 >= min_adopt_score(业务, 角色)``，取值序为
        业务自述（manifest ``min_adopt_score``）→ 角色覆盖 → 全局默认
        ``DEFAULT_MIN_ADOPT_SCORE``。决策模型的概率与 LLM 的 ``confidence`` 走**同一张
        门控表**，两个原语被同等对待（此前 LLM 的置信度完全不参与判断）。

        ``history`` 让路由基于完整对话上下文（而非孤立当前句），天然实现「续接留住出题态」
        而无需手写黏性分支；也支撑「按 agent 能力路由」（manifest 的 ``description``/
        ``actions`` 即能力清单）。

        策略原语均不可用 / 未过门控（都没有命中）时，回落到**无命中引导**：声明了
        ``fallback_guide`` 的业务（生产拓扑即能力自述 ``capability``，ADR-0105）接住并
        提示「自身能做什么」。执行体（tasks / tutor）必须被模型显式路由到，不再作兜底。
        被门控否掉的候选随 ``extra["rejected"]`` 回传（ADR-0107）。
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

        # 策略路由：按配置顺序尝试 决策模型 / LLM 分类 / 交叉校验。
        strategy = get_routing_strategy()
        order = _STRATEGY_ORDER.get(strategy, _STRATEGY_ORDER["auto"])
        # 「有候选但没过门控」与「原语压根没答案」此前都是 ``None``，轨迹上分不出；
        # 上移后把被否掉的候选记下来，随兜底决策一起回传（可观测，不改变落点）。
        rejected: list[dict[str, Any]] = []
        for candidate in order:
            routed = await self._route_candidate(
                candidate, text, visible, deps, history, role=role, rejected=rejected
            )
            if routed is not None:
                return routed

        # 策略原语均未决策（都没有命中）：回落「无命中引导」——声明了 fallback_guide 的
        # 业务接住并提示自身能力（ADR-0105），而不是静默把消息塞给某个执行体。
        return self._fallback_decision(visible, rejected=rejected)

    # ── 路由候选（策略分发） ──
    async def _route_candidate(
        self,
        candidate: str,
        text: str,
        visible: list[str],
        deps: RuntimeDeps,
        history: "list[dict] | None",
        *,
        role: str = "",
        rejected: "list[dict[str, Any]] | None" = None,
    ) -> "RouteDecision | None":
        """按策略名尝试单个路由原语；返回 ``None`` 表示「本原语不决策」，由下一候选兜底。"""
        if candidate == "decision":
            return await self._route_decision(
                text, visible, deps, history, role=role, rejected=rejected
            )
        if candidate == "llm":
            return await self._route_llm(
                text, visible, deps, history, role=role, rejected=rejected
            )
        if candidate == "consensus":
            return await self._route_consensus(
                text, visible, deps, history, role=role, rejected=rejected
            )
        return None

    # ── 采纳门控 ──
    def min_adopt_score(self, business: str, role: str) -> float:
        """该业务在该角色下的采纳门槛：业务自述 → 角色覆盖 → 全局默认（ADR-0107）。

        内核不认识任何业务键：它只读 manifest 自述的 ``min_adopt_score``（``0`` =
        未声明）。角色覆盖为空表时（生产现状，有实测依据）一律走全局默认。
        """
        manifest = self._manifests.get(business)
        declared = float(getattr(manifest, "min_adopt_score", 0.0) or 0.0)
        if declared > 0:
            return declared
        override = get_role_min_adopt_score(role)
        return DEFAULT_MIN_ADOPT_SCORE if override is None else override

    def _adopt(self, business: str, score: float, role: str) -> bool:
        """门控：分数是否够采纳该业务。两个路由原语共用同一张表。"""
        try:
            value = float(score)
        except (TypeError, ValueError):
            return False
        return value >= self.min_adopt_score(business, role)

    async def _route_decision(
        self,
        text: str,
        visible: list[str],
        deps: RuntimeDeps,
        history: "list[dict] | None",
        *,
        role: str = "",
        rejected: "list[dict[str, Any]] | None" = None,
    ) -> "RouteDecision | None":
        """决策模型（Laya-multilingual）主路由；不可用 / 不可见 / **未过门控** → ``None``。

        门控不在此处而在 :meth:`_adopt`（ADR-0107）：模型照实给出「候选 + 分数」，
        分数不够时把候选记进 ``rejected`` 后返回 ``None``——由下一原语或「无命中引导」
        接住，而不是静默消失。
        """
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
        if result is None or result.choice not in visible:
            return None
        score = float(result.prob or 0.0)
        if not self._adopt(result.choice, score, role):
            if rejected is not None:
                rejected.append(
                    {
                        "primitive": "decision",
                        "business": result.choice,
                        "score": score,
                        "min_adopt_score": self.min_adopt_score(result.choice, role),
                    }
                )
            return None
        return RouteDecision(
            business=result.choice,
            name=self.name_of(result.choice),
            extra={
                "routed_by": "decision",
                "level": "decision",
                "prob": score,
                "min_adopt_score": self.min_adopt_score(result.choice, role),
            },
        )

    async def _route_llm(
        self,
        text: str,
        visible: list[str],
        deps: RuntimeDeps,
        history: "list[dict] | None",
        *,
        role: str = "",
        rejected: "list[dict[str, Any]] | None" = None,
    ) -> "RouteDecision | None":
        """通用 LLM 分类路由；不可用 / 不可见 / **未过门控** → ``None`` 回落。

        LLM 自报的 ``confidence`` 与决策模型的概率走**同一张门控表**（ADR-0107）——
        此前它只被记进 ``extra``，从不参与采纳判断，两个原语的门控强度不一致。
        例外：``confidence is None``（模型没填这个字段）时不作比较——那是「未自报」，
        不是「零置信」；拿 0 去比门槛会误杀正确路由（实测 6 条，ADR-0107）。
        """
        decision = await classify_llm(
            deps.provider, history, text, self._manifests, visible
        )
        if decision is None or decision.business not in visible:
            return None
        score = decision.confidence
        if score is not None and not self._adopt(decision.business, float(score), role):
            if rejected is not None:
                rejected.append(
                    {
                        "primitive": "llm",
                        "business": decision.business,
                        "score": score,
                        "min_adopt_score": self.min_adopt_score(decision.business, role),
                    }
                )
            return None
        return RouteDecision(
            business=decision.business,
            name=self.name_of(decision.business),
            extra={
                "routed_by": "llm",
                "level": "llm",
                "confidence": score,
                "min_adopt_score": self.min_adopt_score(decision.business, role),
            },
        )

    async def _route_consensus(
        self,
        text: str,
        visible: list[str],
        deps: RuntimeDeps,
        history: "list[dict] | None",
        *,
        role: str = "",
        rejected: "list[dict[str, Any]] | None" = None,
    ) -> "RouteDecision | None":
        """交叉校验（consensus）：两个原语都跑，**业务一致且各自过门控**才采纳。

        针对的是「自信但错」——决策模型给 0.9 却判错的那类（ticket 12 的 T03 0.927、
        T01 0.833），单一门控无论如何调都挡不住，只有第二个原语能否决。

        - 一致 → ``routed_by="consensus"``（两个分数都带在 extra 里，便于复盘）；
        - 不一致 / 任一不采纳 → ``None`` → 落「无命中引导」（ADR-0105）。

        **代价是显式接受的**：默认策略 ``auto`` 在决策模型采纳时并不调用 LLM，本策略
        每轮消息多一次 LLM 往返。故只作可选档位（``AI_ROUTING_STRATEGY=consensus``），
        不进默认（ticket 13 决策 3）。
        """
        by_decision = await self._route_decision(
            text, visible, deps, history, role=role, rejected=rejected
        )
        by_llm = await self._route_llm(
            text, visible, deps, history, role=role, rejected=rejected
        )
        if by_decision is None or by_llm is None:
            return None
        if by_decision.business != by_llm.business:
            if rejected is not None:
                rejected.append(
                    {
                        "primitive": "consensus",
                        "business": None,
                        "score": 0.0,
                        "min_adopt_score": DEFAULT_MIN_ADOPT_SCORE,
                        "disagreement": [by_decision.business, by_llm.business],
                    }
                )
            return None
        return RouteDecision(
            business=by_decision.business,
            name=self.name_of(by_decision.business),
            extra={
                "routed_by": "consensus",
                "level": "consensus",
                "prob": by_decision.extra.get("prob"),
                "confidence": by_llm.extra.get("confidence"),
            },
        )

    def _fallback_decision(
        self, visible: list[str], *, rejected: "list[dict[str, Any]] | None" = None
    ) -> RouteDecision:
        """策略原语均未决策时的无命中引导：声明 ``fallback_guide`` 的业务接住。

        ADR-0105：tutor 等执行体必须被模型显式路由到，不再作兜底；都没有命中时提示
        「自身能力引导」（生产拓扑即能力自述 capability）。保证路由永不返回 ``None``
        （安全闸门拦截的路径除外，由调用方处理）。

        ``rejected`` 带出「被门控否掉的候选」（ADR-0107 的可观测增强）：此前
        ``routed_by="default"`` 里混着「模型没回」与「回了但 0.43」，轨迹上分不出。
        """
        biz = self._fallback_business(visible)
        extra: dict[str, Any] = {"routed_by": "default", "level": "fallback"}
        if rejected:
            extra["rejected"] = list(rejected)
        return RouteDecision(
            business=biz,
            name=self.name_of(biz) if biz else None,
            extra=extra,
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
    def _gate_ok(
        self, message: str, *, role: str, deps: RuntimeDeps, business: str | None
    ) -> bool:
        """与 ``decide`` 同一道安全 / 可见性闸（T03，候选 2 收口）。

        结构化出题此前直调 ``run(business="tasks")`` 绕过 ``decide``，故未过此闸；
        现聊天路径（decide → run）与结构化路径（invoke_subagent → run）都汇聚到
        ``run``，一致地过同一道闸：

        - 输入安全：``deps.safety`` 配置时校验 ``message``（未配置则跳过，与
          ``decide`` 口径一致）。
        - 角色可见性：``business`` 必须在当前角色可见集内（与 ``decide`` 同款过滤）。
        """
        if business is None:
            return False
        if deps.safety is not None and not deps.safety.check_input(message).safe:
            return False
        if business not in self.visible_businesses(role):
            return False
        return True

    async def run(
        self,
        message: str,
        *,
        role: str,
        ctx: SubAgentContext,
        deps: RuntimeDeps,
        business: str | None = None,
        session: Any = None,
        allow_reroute: bool = False,
    ) -> AsyncIterator[AssistantEvent]:
        """产出统一事件流（AgentRuntime 不负责 SSE 推送，仅产出帧）。

        - 决策由 ``decide`` 计算（端点可预航班复用，避免重复路由）。
        - 依赖（provider/retriever）由 deps 注入；SubAgent 声明 tools 时走真实 tool loop。
        - 每次运行都先过 ``_gate_ok`` 这道安全 / 可见性闸，与聊天 / 结构化两条路径
          共用同一道闸（T03：结构化出题此前直调本方法却绕过了 ``decide`` 的闸，如今
          无论哪条路径都一致过闸）。

        ``allow_reroute`` 只由**自然语言路径**开启（ADR-0109）：业务是路由算出来的，
        算错了才谈得上改判；结构化路径自带 ``business``（规格即意图），把它改判到别
        的业务等于推翻调用方的显式指定。
        """
        sid = ctx.extra.get("session_id") if isinstance(ctx.extra.get("session_id"), str) else None
        if not self._gate_ok(message, role=role, deps=deps, business=business):
            yield error("输入含不适当内容，已拒绝。", code="INPUT_UNSAFE")
            yield done(sid)
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
            yield done(sid)
            return

        # 把 manifest 声明的 SOP 注入 ctx（若 subagent 自身未带）。
        manifest = self._manifests.get(business)
        if not ctx.skills and manifest:
            ctx.skills = manifest.skill_prompt

        try:
            async for ev in run_with_tools(
                agent,
                message,
                ctx,
                session=session,
                hooks=deps.hooks,
                raise_unverified=allow_reroute,
            ):
                yield ev
        except ProviderRequestError as exc:
            # 厂商拒绝请求（认证/限流/网络）：给可操作提示，别把 401 说成「助手执行出错」（ADR-0038）。
            yield error(exc.user_hint, code="PROVIDER_ERROR")
        except UnverifiedAnswerError as exc:
            async for ev in self._reroute_unverified(
                message,
                role=role,
                ctx=ctx,
                deps=deps,
                business=exc.business or business,
                session=session,
            ):
                yield ev
        except Exception as exc:  # noqa: BLE001 — 单 subagent 异常不应让整条流崩
            yield error(f"助手执行出错：{exc}", code="AGENT_ERROR")
        finally:
            yield done(sid)

    # ── 无据重路由（ADR-0109：至多一次） ──
    async def _reroute_unverified(
        self,
        message: str,
        *,
        role: str,
        ctx: SubAgentContext,
        deps: RuntimeDeps,
        business: str | None,
        session: Any = None,
    ) -> AsyncIterator[AssistantEvent]:
        """「这句话不属于我」的接手路径：换一个业务再来一次，换不出落点就照旧硬失败。

        ``requires_tool_data`` 的业务整轮没查过任何数据却给出正文，有两种成因，且
        **在该业务内部无从分辨**（正文都是干净的自然语言，不含任何调用协议痕迹）：

        - **路由误判**（值得修）：这句话本来不需要查数据——「23+45 怎么算」被判给了
          任务学情。此时原硬失败提示让用户「重试 / 换模型」，而重试永远得到同一条错误。
        - **模型能力**（不该动）：小模型流式下产不出原生 function calling，直接编造
          业务数字。此时「换模型」恰恰是正确的提示（ADR-0033 的原型事故）。

        分辨的办法是**再问一次路由原语，但把当前业务排除在候选之外**：

        - 判得出且过门控 → 换业务重来一次。用户侧的代价只是多等一轮；未验证的正文
          早已随异常丢弃，**永不出现在事件轨上**。
        - 判不出 / 不过门控 → 维持 ``TOOL_UNSUPPORTED`` 原文。

        与 ADR-0033 的关系是本设计的全部要点：静默降级是**放行**那段正文（用户拿到
        假数据还以为是真的）；重路由是**换人**——正文丢弃、交接在事件轨上显式可见。

        只问**决策模型**原语（本地 23ms），不问 LLM 分类（p50 1084ms）：它本就产出
        ``probabilities`` 全量分布，排除一项后概率重新归一化但仍**跨 K 可比**
        （``LayaDecisionModel._top_probability`` 取的是概率而非 TypeSafe 的
        ``confidence``），故门控口径不变。决策模型不可用 → 不猜，维持硬失败。

        **至多一次**：候选集已排除当前业务；接手业务再无据时不再重路由
        （``raise_unverified`` 缺省为 ``False``），直接产出原硬失败帧。
        """
        target = await self._reroute_target(
            message, deps, ctx.history, role=role, exclude=business
        )
        if target is None:
            yield error(UNVERIFIED_ANSWER_HINT, code="TOOL_UNSUPPORTED")
            return
        yield thinking(
            f"「{self.name_of(business)}」这次的回答没有数据依据，改由「{target.name}」接手。",
            extra={"routing": True},
        )
        agent = build_subagent(
            self._manifests,
            target.business,
            provider=deps.provider,
            retriever=deps.retriever,
        )
        if agent is None:
            yield error(UNVERIFIED_ANSWER_HINT, code="TOOL_UNSUPPORTED")
            return
        manifest = self._manifests.get(target.business)
        if not ctx.skills and manifest:
            ctx.skills = manifest.skill_prompt
        # 与 :meth:`run` 同款的分级收口：本块在 ``run`` 的 except 分支里执行，
        # 异常若漏出去会绕过 ``run`` 自己的 except 链，故在此自行兜住。
        try:
            async for ev in run_with_tools(
                agent, message, ctx, session=session, hooks=deps.hooks
            ):
                yield ev
        except ProviderRequestError as exc:
            yield error(exc.user_hint, code="PROVIDER_ERROR")
        except Exception as exc:  # noqa: BLE001 — 接手业务出错也不该让整条流崩
            yield error(f"助手执行出错：{exc}", code="AGENT_ERROR")

    async def _reroute_target(
        self,
        text: str,
        deps: RuntimeDeps,
        history: "list[dict] | None",
        *,
        role: str,
        exclude: str | None,
    ) -> "RouteDecision | None":
        """排除当前业务后再问一次决策模型；采纳不到返回 ``None``（即维持硬失败）。

        复用 :meth:`_route_decision` 而非新写一条路径：候选是它算的、门控是它过的、
        「过不了门控就等于没决策」是它定下的语义（ADR-0107）——排除一项只是换了个
        ``visible`` 入参。
        """
        visible = [b for b in self.visible_businesses(role) if b != exclude]
        if not visible:
            return None
        return await self._route_decision(text, visible, deps, history, role=role)

    async def invoke_subagent(
        self,
        message: str,
        *,
        role: str,
        ctx: SubAgentContext,
        deps: RuntimeDeps,
        signal: "str | IntentSignal | None" = None,
        business: str | None = None,
        history: "list[dict] | None" = None,
        session: Any = None,
    ) -> AsyncIterator[AssistantEvent]:
        """聊天 / 结构化两条路径共用的「带闸 runtime 入口」（T03，候选 2）。

        - 聊天路径：传 ``signal``（自由文本 / 动作）→ 内部经 ``decide`` 路由
          （动作直配 / 策略原语 + 安全 / 可见性闸）得到 ``business``，再运行。
        - 结构化出题路径：传已知 ``business``（如 ``"tasks"``）→ **不**重走自然语言
          三级路由，但**仍过同一道安全 / 可见性闸**（经由 ``run``），杜绝此前绕过
          ``decide`` 造成的静默漂移。

        抽绳是本轮全局唯一新增接缝：结构化路径复用「闸 + 事件流」这一段，不复制任何
        路由逻辑。最终都汇入 ``run``（带闸运行），故两条路径共用同一道闸。
        """
        if signal is not None:
            decision = await self.decide(signal, role=role, deps=deps, history=history)
            business = decision.business
            # 路由明确拒绝（business=None）必须显式区分，不得落到 run 的 INPUT_UNSAFE
            # 闸被误标为「输入不安全」（ADR-0081 §2.3：动作命中但角色不可见 → 显式
            # 不可见，禁止静默兜底）。输入不安全由 run 的闸统一拦截。
            if business is None:
                sid = (
                    ctx.extra.get("session_id")
                    if isinstance(ctx.extra.get("session_id"), str)
                    else None
                )
                if (decision.extra or {}).get("reason") == "action_not_visible":
                    yield error("当前角色无权执行该动作。", code="NOT_VISIBLE")
                else:
                    yield error("输入含不适当内容，已拒绝。", code="INPUT_UNSAFE")
                yield done(sid)
                return
        # 经 self.run 动态分派：生产环境走带闸的真实运行；测试桩若覆写 run 也照常生效。
        # ``allow_reroute`` 只在传了 ``signal`` 时开启：那条路径的业务是路由算出来的，
        # 算错了才谈得上改判（ADR-0109）；结构化路径自带 business，不得被改判。
        async for ev in self.run(
            message,
            role=role,
            ctx=ctx,
            deps=deps,
            business=business,
            session=session,
            allow_reroute=signal is not None,
        ):
            yield ev
