"""ADR-0030 抽象收口的回归测试。

四条裂缝各有一组断言钉住：
1. 引擎单一解析链：显式引擎能一路传到 provider（``build_provider(engine=)``）。
2. 发现即注册：discover 出的清单自带 ``agent_cls``，``registry`` 不再手工登记。
3. skills 真消费：manifest 声明的 SOP 文本进 prompt（出题走 persona_hint、伴学走 context）。
4. 路由无硬编码：ADR-0104 移除规则路由、ADR-0105 起 tutor 不再作兜底——都没有命中时
   由声明 ``fallback_guide`` 的业务给出能力引导；``priority`` 只剩「清单呈现顺序 +
   无声明时的最后防线」语义，匹配顺序不再由任何词表决定。
"""
from __future__ import annotations

import asyncio

from agent_core.ports import RuntimeDeps
from agent_core.protocol import EVENT_ASSISTANT_MESSAGE
from agent_core.registry import (
    SubAgentManifest,
    build_subagent,
    discover_subagent_manifests,
    get_subagent_class,
)
from agent_core.runtime import AgentRuntime
from agent_core.subagent import SubAgentContext
from app.ai.subagents.tasks import TasksSubAgent
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
    # ADR-0097：query 解散、guide 删除；ADR-0098：students/question 并入 tasks
    assert set(manifests) >= {"tutor", "tasks"}
    assert "query" not in manifests, "query 已解散（ADR-0097）"
    assert "guide" not in manifests, "guide 已删除（ADR-0097）"
    for business, manifest in manifests.items():
        assert manifest.agent_cls is not None, f"{business} 未发现 agent 类"
        assert get_subagent_class(manifests, business) is manifest.agent_cls

    # skills/*.md 真的被读进来了（此前是死元数据）
    assert "出题 SOP" in manifests["tasks"].skill_prompt
    assert manifests["tutor"].skill_prompt.strip() != ""
    # tasks 的 SOP 纪律已并入 system prompt（原 query_sop 的核心约束逐条在内），
    # 不再有独立 skill 文件——这是 ADR-0097 的刻意选择，防止两份真相源。


def test_build_subagent_uses_discovered_class():
    manifests = discover_subagent_manifests()
    assert isinstance(build_subagent(manifests, "tasks", provider=FakeLLMProvider()), TasksSubAgent)
    assert isinstance(build_subagent(manifests, "tutor", provider=FakeLLMProvider()), TutorSubAgent)
    assert build_subagent(manifests, "nonexistent", provider=FakeLLMProvider()) is None


# ── 3. skills 真消费 ──
class _SpyProvider(FakeLLMProvider):
    """记录最后一次 prompt 侧入参，用于断言 SOP 是否真的进了模型上下文。"""

    def __init__(self) -> None:
        super().__init__()  # 复用替身的计数与失败编排（缺了会丢 schema_calls 等状态）
        self.user_prompt: str | None = None
        self.system_prompt: str | None = None
        self.context: str | None = None

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        self.user_prompt = prompt
        self.system_prompt = system
        async for ev in super().stream(system, prompt, schema=schema, tools=tools, history=history):
            yield ev

    async def tutor(self, *, grade, subject, knowledge_point, context, question, history=None):
        self.context = context
        return await super().tutor(
            grade=grade, subject=subject, knowledge_point=knowledge_point,
            context=context, question=question, history=history,
        )


def test_question_agent_injects_sop_into_system_prompt():
    """SOP 注入模型上下文（ADR-0097 起位置在 tool loop 首轮 system）。

    旧实现把 SOP 拼进出题的 user_prompt（约束解码 run 内 with_skills）；tool loop
    化后 initial_system 统一承载——守护的是「SOP 真的到达模型」，不是位置本身。
    """
    provider = _SpyProvider().script("generate_questions")
    agent = TasksSubAgent(provider=provider)
    ctx = SubAgentContext(role="teacher", message="帮我出3道三年级数学选择题", skills="SOP-XYZ")

    async def _go():
        return [ev async for ev in agent.run(ctx.message or "", ctx)]

    asyncio.run(_go())
    assert provider.system_prompt is not None
    assert "SOP-XYZ" in provider.system_prompt


def test_tutor_agent_injects_sop_into_context():
    provider = _SpyProvider()
    agent = TutorSubAgent(provider=provider)
    ctx = SubAgentContext(role="student", message="为什么分数要通分", skills="SOP-ABC")

    async def _go():
        return [ev async for ev in agent.run(ctx.message or "", ctx)]

    asyncio.run(_go())
    assert provider.context is not None
    assert "SOP-ABC" in provider.context


def test_real_sop_does_not_trip_input_safety():
    """回归：真实的 tutor_sop.md 含「越狱/成人/暴力/政治」等安全词。

    SOP 是系统受控资产，必须在输入闸门**之后**注入。若把它并进 check_input 的
    扫描范围，每条学生提问都会被自己的安全 SOP 判为不安全（整条伴学链路报废）。
    """
    sop = discover_subagent_manifests()["tutor"].skill_prompt
    assert not check_input(sop).safe  # SOP 本身确实会命中词表

    agent = TutorSubAgent(provider=_SpyProvider())
    ctx = SubAgentContext(role="student", message="为什么分数要通分", skills=sop)

    async def _go():
        return [ev async for ev in agent.run(ctx.message or "", ctx)]

    events = asyncio.run(_go())
    assistant_messages = [e for e in events if e.eventType == EVENT_ASSISTANT_MESSAGE]
    assert assistant_messages, "伴学未产出任何回复"
    # blocked=True 意味着被安全闸门拦下（本应正常答疑）
    assert not any(e.blocked for e in assistant_messages)


# ── 4. 路由无硬编码（ADR-0104 规则移除；ADR-0105 无命中引导 = 声明的 fallback_guide） ──
def _manifest(
    business: str,
    *,
    priority: int,
    roles: list[str] | None = None,
    fallback_guide: bool = False,
):
    return SubAgentManifest(
        business=business,
        name=business,
        priority=priority,
        roles=roles if roles is not None else ["teacher", "student"],
        fallback_guide=fallback_guide,
    )


def test_decide_prefers_declared_fallback_guide():
    """都没有命中时，落**声明了 fallback_guide** 的业务（ADR-0105），与 priority 无关。

    生产拓扑即能力自述 capability：tutor(-10) 数值更小也不再接住——执行体必须被
    模型显式路由到，无命中时给的是「自身能力引导」。
    """
    manifests = {
        "tutor": _manifest("tutor", priority=-10),
        "capability": _manifest("capability", priority=16, fallback_guide=True),
    }
    rt = AgentRuntime(manifests)
    decision = asyncio.run(
        rt.decide(
            "都没有命中的一句话",
            role="teacher",
            deps=RuntimeDeps(provider=FakeLLMProvider()),
        )
    )
    assert decision.business == "capability"
    assert decision.extra.get("routed_by") == "default"


def test_decide_last_resort_falls_back_to_lowest_priority_business():
    """没有任何业务声明 fallback_guide 时的最后防线：可见集中 priority 最小者。

    ADR-0105：该路径在当前生产拓扑不可达（capability 双端可见且已声明），仅为将来
    的清单变化保住「路由永不返回 None」。
    """
    manifests = {
        "a": _manifest("a", priority=5),
        "z": _manifest("z", priority=-5),
    }
    rt = AgentRuntime(manifests)
    decision = asyncio.run(
        rt.decide(
            "今天天气不错",
            role="teacher",
            deps=RuntimeDeps(provider=FakeLLMProvider()),
        )
    )
    assert decision.business == "z"
    assert decision.extra.get("routed_by") == "default"


def test_decide_visible_set_bounds_fallback():
    """引导 / 最后防线都只在**当前角色可见集**里挑：声明业务或低优先级业务对角色
    不可见时跳过它。"""
    manifests = {
        "a": _manifest("a", priority=5),
        "guide": _manifest("guide", priority=16, fallback_guide=True, roles=["student"]),
        "z": _manifest("z", priority=-5, roles=["student"]),
    }
    rt = AgentRuntime(manifests)
    decision = asyncio.run(
        rt.decide(
            "随便一句",
            role="teacher",
            deps=RuntimeDeps(provider=FakeLLMProvider()),
        )
    )
    assert decision.business == "a"
