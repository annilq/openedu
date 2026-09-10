"""ADR-0030 抽象收口的回归测试。

四条裂缝各有一组断言钉住：
1. 引擎单一解析链：显式引擎能一路传到 provider（``build_provider(engine=)``）。
2. 发现即注册：discover 出的清单自带 ``agent_cls``，``registry`` 不再手工登记。
3. skills 真消费：manifest 声明的 SOP 文本进 prompt（出题走 persona_hint、伴学走 context）。
4. 路由无硬编码：匹配顺序完全由 manifest 的 ``priority`` 决定。
"""
from __future__ import annotations

import asyncio

from agent_core.protocol import EVENT_ASSISTANT_MESSAGE
from agent_core.registry import (
    SubAgentManifest,
    build_subagent,
    discover_subagent_manifests,
    get_subagent_class,
)
from agent_core.router import classify
from agent_core.subagent import SubAgentContext
from app.ai.subagents.question import QuestionSubAgent
from app.ai.subagents.tutor import TutorSubAgent
from app.domain import build_provider
from app.domain.genkit_provider import GenkitProvider
from app.domain.safety import check_input
from tests.utils.fake_provider import FakeLLMProvider


# ── 1. 引擎单一解析链 ──
def test_build_provider_carries_explicit_engine():
    sentinel = object()
    provider = build_provider(engine=sentinel)
    assert isinstance(provider, GenkitProvider)
    assert provider._engine is sentinel


def test_build_provider_without_engine_defers_to_global_resolution():
    """未给引擎时不应把 None 当成「已解析」，仍走全局 resolve_engine（ADR-0030）。"""
    assert build_provider()._engine is None


# ── 2. 发现即注册 ──
def test_discovery_picks_up_agent_class_and_skill_prompt():
    manifests = discover_subagent_manifests()
    assert set(manifests) >= {"tutor", "question", "query"}
    assert "tasks" not in manifests, "tasks 已被 query 吸收（ADR-0033 决策 6）"
    for business, manifest in manifests.items():
        assert manifest.agent_cls is not None, f"{business} 未发现 agent 类"
        assert get_subagent_class(manifests, business) is manifest.agent_cls

    # skills/*.md 真的被读进来了（此前是死元数据）
    assert "出题 SOP" in manifests["question"].skill_prompt
    assert manifests["tutor"].skill_prompt.strip() != ""
    assert "学情查询 SOP" in manifests["query"].skill_prompt


def test_build_subagent_uses_discovered_class():
    manifests = discover_subagent_manifests()
    assert isinstance(build_subagent(manifests, "question", provider=FakeLLMProvider()), QuestionSubAgent)
    assert isinstance(build_subagent(manifests, "tutor", provider=FakeLLMProvider()), TutorSubAgent)
    assert build_subagent(manifests, "nonexistent", provider=FakeLLMProvider()) is None


# ── 3. skills 真消费 ──
class _SpyProvider(FakeLLMProvider):
    """记录最后一次 prompt 侧入参，用于断言 SOP 是否真的进了模型上下文。"""

    def __init__(self) -> None:
        self.user_prompt: str | None = None
        self.context: str | None = None

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        self.user_prompt = prompt
        async for ev in super().stream(system, prompt, schema=schema, tools=tools, history=history):
            yield ev

    async def tutor(self, *, grade, subject, knowledge_point, context, question, history=None):
        self.context = context
        return await super().tutor(
            grade=grade, subject=subject, knowledge_point=knowledge_point,
            context=context, question=question, history=history,
        )


def test_question_agent_injects_sop_into_user_prompt():
    provider = _SpyProvider()
    agent = QuestionSubAgent(provider=provider)
    ctx = SubAgentContext(role="parent", message="帮我出3道三年级数学选择题", skills="SOP-XYZ")

    async def _go():
        return [ev async for ev in agent.run(ctx.message or "", ctx)]

    asyncio.run(_go())
    assert provider.user_prompt is not None
    assert "SOP-XYZ" in provider.user_prompt


def test_tutor_agent_injects_sop_into_context():
    provider = _SpyProvider()
    agent = TutorSubAgent(provider=provider)
    ctx = SubAgentContext(role="child", message="为什么分数要通分", skills="SOP-ABC")

    async def _go():
        return [ev async for ev in agent.run(ctx.message or "", ctx)]

    asyncio.run(_go())
    assert provider.context is not None
    assert "SOP-ABC" in provider.context


def test_real_sop_does_not_trip_input_safety():
    """回归：真实的 tutor_sop.md 含「越狱/成人/暴力/政治」等安全词。

    SOP 是系统受控资产，必须在输入闸门**之后**注入。若把它并进 check_input 的
    扫描范围，每条娃娃提问都会被自己的安全 SOP 判为不安全（整条伴学链路报废）。
    """
    sop = discover_subagent_manifests()["tutor"].skill_prompt
    assert not check_input(sop).safe  # SOP 本身确实会命中词表

    agent = TutorSubAgent(provider=_SpyProvider())
    ctx = SubAgentContext(role="child", message="为什么分数要通分", skills=sop)

    async def _go():
        return [ev async for ev in agent.run(ctx.message or "", ctx)]

    events = asyncio.run(_go())
    assistant_messages = [e for e in events if e.eventType == EVENT_ASSISTANT_MESSAGE]
    assert assistant_messages, "伴学未产出任何回复"
    # blocked=True 意味着被安全闸门拦下（本应正常答疑）
    assert not any(e.blocked for e in assistant_messages)


# ── 4. 路由无硬编码 ──
def _manifest(business: str, *, priority: int, triggers: list[str], hints: list[str]):
    return SubAgentManifest(
        business=business,
        name=business,
        triggers=triggers,
        hints=hints,
        priority=priority,
    )


def _route(text: str, available: list[str], manifests: dict) -> str:
    return asyncio.run(classify(text, available=available, manifests=manifests))


def test_router_orders_by_manifest_priority_only():
    """路由顺序只认 manifest 的 priority：业务名对 router 完全不可见。"""
    manifests = {
        "low": _manifest("low", priority=-10, triggers=["题目"], hints=["题"]),
        "high": _manifest("high", priority=10, triggers=["作业"], hints=["作业"]),
    }
    # 两业务都能匹配时，priority 高者胜
    assert _route("查看作业里的题目", ["low", "high"], manifests) == "high"
    # 只有低优先级命中 → 低优先级
    assert _route("来几道题", ["low", "high"], manifests) == "low"
    # 规则全未命中 → hints 兜底
    assert _route("随便聊聊", ["low", "high"], manifests) == "low"


def test_router_falls_back_to_lowest_priority():
    manifests = {
        "a": _manifest("a", priority=5, triggers=["出"], hints=[]),
        "z": _manifest("z", priority=-5, triggers=["讲"], hints=[]),
    }
    assert _route("今天天气不错", ["a", "z"], manifests) == "z"
