"""Agent Runtime（ADR-0024 / 0025 / 0026）：统一对话编排。

职责：
1. 文件夹发现：扫描 ``app/ai/subagents/<business>/`` 加载 manifest（业务键/可见角色/
   触发词/工具/技能），新 subagent = 丢一个文件夹。
2. 意图路由：混合路由（manifest.triggers 规则优先 → 可选 LLM 分类 → 启发式兜底）。
3. 角色感知：按当前 role 过滤可见 subagent（娃娃端仅伴学答疑，ADR-0026）。
4. 事件流：调用 SubAgent.run 产出 AG-UI 事件帧（USER_MESSAGE / THINKING / TOOL_CALL /
   TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE），由端点以 SSE 推送。
5. 会话持久化交给端点（复用 Conversation/Message，ADR-0022 升级为助手会话，supersede）。

本类无状态；每次请求经 ``run`` 产出「路由决策 + 事件流」二元组，端点负责鉴权/配额/落库。
路由决策以 ``RouteDecision`` 结构化对象显式返回（business / name / subject），不再经
THINKING 帧的 ``extra`` 隐式透传，消除端点对事件信封的隐式契约依赖（见 #2）。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import AsyncIterator
from uuid import UUID

from sqlmodel import Session

from app.ai.engine import resolve_engine
from app.ai.runtime.intent_router import classify
from app.ai.runtime.manifest import SubAgentManifest, discover_subagent_manifests
from app.ai.runtime.protocol import (
    AssistantEvent,
    done,
    error,
    run_started,
    thinking,
    user_message,
)
from app.domain import build_provider, build_retriever
from app.domain.safety import check_input


@dataclass
class RouteDecision:
    """一次路由的结构化决策，由 ``run``/``decide`` 显式返回供端点消费。

    - ``business``：路由到的业务键；``None`` 表示输入被安全闸门拦截（不路由）。
    - ``name``：业务可读名（来自 manifest.name）。
    - ``subject``：仅 tutor 域解析的学科（child 恒为 tutor）；端点配额与 TutorLog 复用，
      避免端点二次调用 ``detect_subject``（见 #3）。
    """

    business: str | None
    name: str | None
    subject: str | None = None


class AgentRuntime:
    def __init__(self, manifests: dict[str, SubAgentManifest]) -> None:
        self._manifests = manifests

    # ── 发现 ──
    @classmethod
    def discover(cls) -> "AgentRuntime":
        return cls(discover_subagent_manifests())

    # ── 角色可见性 ──
    def visible_businesses(self, role: str) -> list[str]:
        """按当前角色过滤可见 subagent（ADR-0026：娃娃端仅伴学答疑）。"""
        return [b for b, m in self._manifests.items() if role in m.roles]

    def name_of(self, business: str) -> str:
        m = self._manifests.get(business)
        return m.name if m else business

    # ── 路由决策（纯计算，不流式、不构建依赖） ──
    async def decide(
        self,
        message: str,
        *,
        role: str,
        child_id: UUID | None = None,
        parent_id: UUID | None = None,
        session: Session | None = None,
    ) -> RouteDecision:
        """解析路由决策：角色可见性 → 安全闸门 → 混合路由 → subject。

        不产出任何事件帧，也不构建 provider/retriever/engine，便于端点在进入流式前
        做预航班（配额判定）并显式拿到 ``business`` / ``subject``，消除 ``extra`` 隐式契约。
        """
        visible = self.visible_businesses(role)

        # 娃娃端输入安全（首层防御；TutorService 内部还有第二层）
        if role == "child" and not check_input(message).safe:
            return RouteDecision(business=None, name=None, subject=None)

        business = await classify(message, available=visible, manifests=self._manifests)

        # 角色可见性是唯一真相源：classify(available=visible) 只会在 visible 内决策，
        # 无需 child→tutor 的二次硬覆盖（原先那行双源真相、永不适用的死代码已删除）。
        # 防御性兜底：若 classify 越界（理论不发生），回退可见集首个，绝不落到 child 不可见业务。
        if business not in visible:
            business = visible[0] if visible else "tutor"

        name = self.name_of(business)
        # subject 仅 tutor 域解析（child 恒为 tutor）；一次计算，端点配额与 TutorLog 复用
        subject = self._detect_subject(message) if business == "tutor" else None
        return RouteDecision(business=business, name=name, subject=subject)

    @staticmethod
    def _detect_subject(message: str) -> str:
        # 惰性导入以打破 app.ai.subagents ↔ app.ai.runtime 的循环依赖。
        from app.ai.subagents.tutor import detect_subject

        return detect_subject(message)

    # ── 运行 ──
    async def run(
        self,
        message: str,
        *,
        role: str,
        child_id: UUID | None = None,
        parent_id: UUID | None = None,
        session: Session | None = None,
        model: str | None = None,
        session_id: str | None = None,
        history: list[dict] | None = None,
        focus_interest: list[str] | None = None,
        decision: RouteDecision | None = None,
    ) -> tuple[RouteDecision, AsyncIterator[AssistantEvent]]:
        """返回 ``(路由决策, 事件流)``。

        - 决策由 ``decide`` 计算（端点可预航班复用，避免重复路由）。
        - 事件流惰性产出：RUN_STARTED / USER_MESSAGE / 路由 THINKING / 业务帧 / DONE。
        - 依赖（provider/retriever/engine）延迟到路由确定后、流体内构建，避免对非出题
          业务（如 tutor）做无用的 RAG/LLM 初始化（见 #4）。
        """
        if decision is None:
            decision = await self.decide(
                message, role=role, child_id=child_id, parent_id=parent_id, session=session
            )

        # 惰性导入以打破 app.ai.subagents ↔ app.ai.runtime 的循环依赖。
        from app.ai.subagents import SubAgentContext, build_subagent
        from app.ai.subagents.base import BaseSubAgent

        async def _stream() -> AsyncIterator[AssistantEvent]:
            yield run_started()
            yield user_message(message)

            # routing 标记：前端据此把「路由状态」与「业务推理增量」区分开，
            # 否则这句会被当成出题思路拼进内联推理区。
            yield thinking("正在理解你的需求，并选择最合适的助手…", extra={"routing": True})

            # 输入被安全闸门拦截：直接 ERROR + DONE，不路由到任何 subagent。
            if decision.business is None:
                yield error("输入含不适当内容，已拒绝。", code="INPUT_UNSAFE")
                yield done(session_id)
                return

            name = decision.name or decision.business
            yield thinking(f"已选择助手：{name}", extra={"routing": True})

            # 依赖延迟构建：仅路由确定且 subagent 存在后初始化（见 #4）。
            provider = build_provider()
            retriever = build_retriever()
            # child 经 parent_id 解析引擎（继承家长 ModelConfig / 全局默认），
            # 不再要求客户端显式带 model（原三元条件使 child 永不拿到引擎，见 #5）。
            engine = (
                resolve_engine(model, parent_id=parent_id, session=session)
                if parent_id is not None
                else None
            )
            agent: BaseSubAgent | None = build_subagent(
                decision.business, provider=provider, retriever=retriever, engine=engine
            )
            if agent is None:
                yield error(f"未找到可用的助手：{decision.business}", code="NO_AGENT")
                yield done(session_id)
                return

            ctx = SubAgentContext(
                role=role,
                child_id=child_id,
                parent_id=parent_id,
                model=model,
                question=message,
                focus_interest=focus_interest,
                history=history,
            )

            try:
                async for ev in agent.run(message, ctx, session=session):
                    yield ev
            except Exception as exc:  # noqa: BLE001 — 单 subagent 异常不应让整条流崩
                yield error(f"助手执行出错：{exc}", code="AGENT_ERROR")
            finally:
                yield done(session_id)

        return decision, _stream()
