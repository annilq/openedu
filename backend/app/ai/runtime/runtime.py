"""Agent Runtime（ADR-0024 / 0025 / 0026）：统一对话编排。

职责：
1. 文件夹发现：扫描 ``app/ai/subagents/<business>/`` 加载 manifest（业务键/可见角色/
   触发词/工具/技能），新 subagent = 丢一个文件夹。
2. 意图路由：混合路由（manifest.triggers 规则优先 → 可选 LLM 分类 → 启发式兜底）。
3. 角色感知：按当前 role 过滤可见 subagent（娃娃端仅伴学答疑，ADR-0026）。
4. 事件流：调用 SubAgent.run 产出 AG-UI 事件帧（USER_MESSAGE / THINKING / TOOL_CALL /
   TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE），由端点以 SSE 推送。
5. 会话持久化交给端点（复用 Conversation/Message，ADR-0022 升级为助手会话，supersede）。

本类无状态；每次请求经 ``run`` 产出事件，端点负责鉴权/配额/落库。
"""
from __future__ import annotations

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
        focus_interest: str | None = None,
    ) -> AsyncIterator[AssistantEvent]:
        """产出一次对话的完整 AG-UI 事件流。

        - 对娃娃端先做输入安全校验（ADR-008 防御层）。
        - 路由 → 加载 SubAgent → 委托其 run 产出业务事件。
        - 路由决策以 THINKING 帧（extra.business）透出，供端点写 Conversation.kind。
        """
        # 惰性导入以打破 app.ai.subagents ↔ app.ai.runtime 的循环依赖。
        from app.ai.subagents import SubAgentContext, build_subagent
        from app.ai.subagents.base import BaseSubAgent

        visible = self.visible_businesses(role)

        yield run_started()
        yield user_message(message)

        # 娃娃端输入安全（首层防御；TutorService 内部还有第二层）
        if role == "child" and not check_input(message).safe:
            yield error("输入含不适当内容，已拒绝。", code="INPUT_UNSAFE")
            yield done(session_id)
            return

        yield thinking("正在理解你的需求，并选择最合适的助手…")

        business = await classify(
            message, available=visible, manifests=self._manifests
        )

        # 双保险：娃娃端绝不允许路由到出题/查询（仅伴学）
        if role == "child" and business != "tutor":
            business = "tutor"

        name = self.name_of(business)
        yield thinking(f"已选择助手：{name}", extra={"business": business, "name": name, "routing": True})

        # 构建 SubAgent（复用既有 provider/retriever；engine 解析真实模型）
        provider = build_provider()
        retriever = build_retriever()
        engine = (
            resolve_engine(model, parent_id=parent_id, session=session)
            if model and parent_id is not None
            else None
        )
        agent: BaseSubAgent | None = build_subagent(
            business, provider=provider, retriever=retriever, engine=engine
        )
        if agent is None:
            yield error(f"未找到可用的助手：{business}", code="NO_AGENT")
            yield done(session_id)
            return

        ctx = SubAgentContext(
            role=role,
            child_id=child_id,
            parent_id=parent_id,
            model=model,
            question=message,
            focus_interest=focus_interest,
        )

        try:
            async for ev in agent.run(message, ctx, session=session):
                yield ev
        except Exception as exc:  # noqa: BLE001 — 单 subagent 异常不应让整条流崩
            yield error(f"助手执行出错：{exc}", code="AGENT_ERROR")
        finally:
            yield done(session_id)
