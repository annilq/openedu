"""agent_core Agent Runtime（业务无关的统一编排）。

职责：
1. 文件夹发现：扫描 subagent 文件夹加载 manifest（业务键/可见角色/触发词/skills）。
2. 意图路由：规则匹配 → 启发式兜底。
3. 角色感知：按当前 role 过滤可见 subagent。
4. 事件流：调用 SubAgent.run / run_with_tools 产出 AG-UI 事件帧，由端点以 SSE 推送。
5. 真实 tool loop：SubAgent 声明 tools 时，runtime 以「选型→执行→回灌→循环」调度。

本模块**零业务依赖**：模型/检索/安全均为注入的抽象 seam（RuntimeDeps），不 import 任何
app.* 符号。会话持久化交给端点（复用业务自身的会话表）。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, AsyncIterator

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
from agent_core.router import IntentSignal, match_action
from agent_core.router import classify as _classify
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools


@dataclass
class RouteDecision:
    """一次路由的结构化决策，由 ``run``/``decide`` 显式返回供端点消费。

    - ``business``：路由到的业务键；``None`` 表示输入被安全闸门拦截（不路由）。
    - ``name``：业务可读名（来自 manifest.name）。
    - ``trigger``：规则匹配命中的触发词（启发式 / 兜底 / 动作直配为 ``None``）。
      ADR-0098：业务合并后（question 并入 tasks），调用方靠它分子意图——
      如出题槽位预检按「命中词落在哪个 intent 组」选 schema。
    - ``extra``：路由附加信息（如置信度），业务无关。
    """

    business: str | None
    name: str | None = None
    trigger: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)


# 路由用历史窗口上限（Laya-multilingual 上下文 1024 tok，取近期轮次足够消歧）。
# 近期 N 轮即可覆盖「上一轮出题 → 本轮补参数 / 作答」这类续接消歧，不撑爆 state。
ROUTING_HISTORY_LIMIT = 12


def _build_routing_state(
    history: "list[dict] | None", text: str
) -> str:
    """把「近期历史 + 当前消息」拼成决策模型的 ``state`` 文本。

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


def _capability_text(manifest: "SubAgentManifest") -> str:
    """把 manifest 的 ``name`` / ``description`` / ``actions`` 拼成决策模型的选项描述。

    即「按 agent 能力路由」的能力清单：新增 subagent 自动扩展候选，无需改路由代码。
    """
    bits = [manifest.name]
    if manifest.description:
        bits.append(manifest.description)
    if manifest.actions:
        bits.append("actions: " + ", ".join(manifest.actions))
    return "\n".join(bits)


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
        """解析路由决策：角色可见性 → 安全闸门 → 结构化动作直配 → 决策模型 → 规则兜底。

        输入接受 ``str``（迁移期兼容）或 ``IntentSignal``；不产出事件帧、不构建 provider。
        端点可据此在流式前做预航班（配额判定）。

        四级路由（动作直配最前，决策模型主路由，规则作确定性兜底）：

        1. **动作直配**：``signal.action`` 与各 manifest ``actions`` 等值匹配，命中即路由，
           不参与优先级排序、不与文本竞争（ADR-0081，不变）。
        2. **决策模型主路由**：``deps.decision_model`` 可用时，以「近期 history + 当前消息」
           为 ``state``、可见 business 的能力清单为选项，调用其返回「业务 + 校准概率」；
           置信则路由（``extra.routed_by = "decision"``），不置信或不可用则回落规则。
        3. **规则匹配** / 4. **启发式兜底**：现有文本路由（``classify``），行为不变，
           作决策模型不可用时的确定性兜底与离线测试用。

        ``history`` 让路由基于完整对话上下文（而非孤立当前句），天然实现「续接留住出题态」
        而无需手写黏性分支；也支撑「按 agent 能力路由」（manifest 的 ``description``/
        ``actions`` 即能力清单）。

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

        # 第二级：决策模型主路由（Laya-multilingual 等）。不可用 / 低置信 → 落规则兜底。
        dm = deps.decision_model
        if dm is not None and dm.available():
            state = _build_routing_state(history, text)
            options = [
                DecisionOption(
                    key=biz, label=_capability_text(self._manifests[biz])
                )
                for biz in visible
            ]
            try:
                result = await dm.decide(state=state, options=options)
            except Exception:  # noqa: BLE001 — 决策模型异常不应击穿路由
                result = None
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

        decision = await _classify(text, available=visible, manifests=self._manifests)
        # 角色可见性是唯一真相源：classify 只在 visible 内决策。
        biz = decision.business
        if biz not in visible:
            biz = visible[0] if visible else None
        return RouteDecision(
            business=biz,
            name=self.name_of(biz) if biz else None,
            trigger=decision.trigger,
        )

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
