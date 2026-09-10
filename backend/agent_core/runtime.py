"""agent_core Agent Runtime（业务无关的统一编排）。

职责：
1. 文件夹发现：扫描 subagent 文件夹加载 manifest（业务键/可见角色/触发词/skills）。
2. 意图路由：规则匹配 → 启发式兜底 →（可选）LLM 分类。
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

from agent_core.ports import RuntimeDeps
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
from agent_core.router import classify as _classify
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools


@dataclass
class RouteDecision:
    """一次路由的结构化决策，由 ``run``/``decide`` 显式返回供端点消费。

    - ``business``：路由到的业务键；``None`` 表示输入被安全闸门拦截（不路由）。
    - ``name``：业务可读名（来自 manifest.name）。
    - ``extra``：路由附加信息（如置信度），业务无关。
    """

    business: str | None
    name: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)


class AgentRuntime:
    def __init__(self, manifests: dict[str, SubAgentManifest]) -> None:
        self._manifests = manifests

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
        self, message: str, *, role: str, deps: RuntimeDeps
    ) -> RouteDecision:
        """解析路由决策：角色可见性 → 安全闸门 → 混合路由。

        不产出事件帧、不构建 provider。端点可据此在流式前做预航班（配额判定）。
        """
        visible = self.visible_businesses(role)

        # 输入安全（首层防御）：被拦截则不路由。
        if deps.safety is not None and not deps.safety.check_input(message).safe:
            return RouteDecision(business=None, name=None)

        business = await _classify(
            message, available=visible, manifests=self._manifests, llm_classify=deps.llm_classify
        )
        # 角色可见性是唯一真相源：classify 只在 visible 内决策。
        if business not in visible:
            business = visible[0] if visible else None
        return RouteDecision(business=business, name=self.name_of(business) if business else None)

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
            async for ev in run_with_tools(agent, message, ctx, session=session):
                yield ev
        except Exception as exc:  # noqa: BLE001 — 单 subagent 异常不应让整条流崩
            yield error(f"助手执行出错：{exc}", code="AGENT_ERROR")
        finally:
            yield done(ctx.extra.get("session_id") if isinstance(ctx.extra.get("session_id"), str) else None)
