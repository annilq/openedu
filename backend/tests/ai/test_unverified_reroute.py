"""无据重路由（ADR-0109）：业务自述「结论必须有据」却整轮没查过数据时的接手路径。

被改动的原来是 ADR-0033 的**末闸**——``requires_tool_data`` 的业务整轮没执行过
任何工具却产出正文 → 硬失败 ``TOOL_UNSUPPORTED``（真机事故 ``c361dd01``：本地小模型
流式下不产原生 function calling，直接编出「3 个学生在册」）。那道闸守的是「绝不静默
降级」：没有数据支撑的结论一个字都不许到用户面前。

**本文件守的是它没有变成静默降级**：换业务是「换人」，不是「放行」——

- 未验证的正文随异常丢弃，**在所有用例里都断言它没出现在任何事件文本中**
  （这是 ADR-0033 的验收口径，只是落点从「报错」变成「换人」）；
- 换不出落点（决策模型没回 / 不过门控 / 没有别的可见业务）时，提示语与原来逐字一致；
- 至多换一次，接手的业务再无据就直接收原硬失败。

另一条独立的红线：**结构化路径不得被改判**——那条路径的业务是调用方显式指定的
（规格即意图），不是路由算出来的，算错的前提不成立。

为什么值得修：原提示语让 A 类用户「重试 / 换模型」，而 A 类（「23+45 怎么算」被判给
任务学情）重试一万次也是同一条错误——问题根本不在模型。

本文件不触真实模型（CI 红线）：provider 与决策模型都是脚本化替身。
"""
from __future__ import annotations

import asyncio

import pytest

from agent_core.errors import UnverifiedAnswerError
from agent_core.ports import (
    DecisionModel,
    DecisionResult,
    LLMProvider,
    RuntimeDeps,
    TextDelta,
)
from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_ERROR,
    EVENT_THINKING,
    assistant_message,
)
from agent_core.registry import SubAgentManifest
from agent_core.runtime import AgentRuntime
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools
from agent_core.tools import ToolSpec
from tests.utils.fake_provider import FakeLLMProvider

# 一句像模像样的「未查先答」（与 ADR-0033 回归用例同形态：正文干净、没有任何协议标记）。
_FABRICATED = "当前名下的学生有3个，分别是：小明、小红、小华。"
_HANDOVER_ANSWER = "由接手业务给出的回答。"


# ─────────────────────────────── 替身 ───────────────────────────────


class _AnswersWithoutTools(LLMProvider):
    """只吐正文、从不发起工具调用（模拟「模型直接作答」）。

    ``requests`` 是断言「换人没有失控」的计数器：换一次人最多多问一次。
    """

    def __init__(self, text: str = _FABRICATED) -> None:
        self.text = text
        self.requests = 0

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        self.requests += 1
        yield TextDelta(delta=self.text)


class _StubDecisionModel(DecisionModel):
    """内存桩：返回预设 ``DecisionResult``（分数由用例给定，桩自己不做门控）。"""

    def __init__(self, result: DecisionResult | None = None) -> None:
        self._result = result
        self.calls = 0

    def available(self) -> bool:
        return True

    async def decide(self, *, state: str, options):  # noqa: ANN001 — 测试桩
        self.calls += 1
        return self._result


def _tool_spec() -> ToolSpec:
    """一个恒成功的读工具：形式上有工具可用，「不调」才是模型自己的选择。"""

    async def _handler(args, *, ctx, session=None) -> dict:
        return {"ok": True}

    return ToolSpec(
        name="list_x",
        label="查数据",
        description="按条件查一条数据",
        schema={"type": "object", "properties": {}},
        handler=_handler,
    )


class _DataAgent(BaseSubAgent):
    """结论必须有据的最小业务（形态与 tasks 一致）：有工具，但本用例里模型不调。"""

    business = "data_a"
    requires_tool_data = True

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        self.tools = [_tool_spec()]

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        yield assistant_message("不应走到一次性 run。")


def _as_business(cls: type[BaseSubAgent], business: str, name: str) -> type[BaseSubAgent]:
    """同一个执行体的别名子类（清单里两个业务，便于编排「接手者也是它」）。"""
    return type(cls.__name__, (cls,), {"business": business, "_alias": name})


class _PlainAgent(BaseSubAgent):
    """接手方：无工具、直接作答（形态与 tutor 一致）。"""

    business = "plain"

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        yield assistant_message(_HANDOVER_ANSWER)


def _ctx() -> SubAgentContext:
    return SubAgentContext(role="teacher", message="", history=None, extra={})


def _drain(stream) -> list:
    return asyncio.run(_collect(stream))


async def _collect(stream) -> list:
    return [ev async for ev in stream]


def _all_text(events) -> str:
    return "".join(
        (ev.text or ev.message or "") for ev in events
    )


def _errors(events) -> list:
    return [ev for ev in events if ev.eventType == EVENT_ERROR]


def _handovers(events) -> list[str]:
    return [
        ev.text
        for ev in events
        if ev.eventType == EVENT_THINKING and "接手" in (ev.text or "")
    ]


def _runtime(extra: dict[str, SubAgentManifest] | None = None) -> AgentRuntime:
    """任务式清单：``data_a``（无据者）+ ``plain``（接手者），可再加业务。"""
    manifests = {
        "data_a": SubAgentManifest(
            business="data_a",
            name="数据业务",
            description="必须有据",
            roles=["teacher"],
            priority=10,
            agent_cls=_DataAgent,
        ),
        "plain": SubAgentManifest(
            business="plain",
            name="讲解业务",
            description="直接作答",
            roles=["teacher"],
            priority=5,
            agent_cls=_PlainAgent,
        ),
    }
    manifests.update(extra or {})
    return AgentRuntime(manifests)


# ───────────────────── 接缝：默认仍是硬失败，opt-in 才抛 ─────────────────────


def _run_loop(**kw):
    agent = _DataAgent(provider=_AnswersWithoutTools())
    return _drain(run_with_tools(agent, "一句话", _ctx(), **kw))


def test_hard_failure_is_unchanged_by_default():
    """不 opt-in 时末闸与 ADR-0033 逐字一致（换人是 runtime 的选择，不是共享默认）。"""
    events = _run_loop()
    assert [ev.code for ev in _errors(events)] == ["TOOL_UNSUPPORTED"]
    assert _FABRICATED not in _all_text(events)


def test_opt_in_raises_carrying_the_discarded_text():
    """opt-in 后改为抛异常：正文随异常带走，事件轨上什么都没留下。"""
    with pytest.raises(UnverifiedAnswerError) as excinfo:
        _run_loop(raise_unverified=True)

    assert excinfo.value.business == "data_a"
    assert excinfo.value.text == _FABRICATED
    # 抛出的位置在末闸：正文还没进过任何事件
    assert "TOOL_UNSUPPORTED" not in str(excinfo.value)


# ───────────────────── 换人：换得出就把话接过去 ─────────────────────


def test_reroute_hands_over_when_router_names_another_business():
    """排除当前业务后决策模型点名了别人 → 换人重来。

    验收点有两个，缺一不可：① 无据正文一个字都没外发（ADR-0033 的口径）；
    ② 接手方真的把话接了过去（否则只是把报错推迟了一轮）。
    """
    dm = _StubDecisionModel(DecisionResult(choice="plain", prob=0.9))
    provider = _AnswersWithoutTools()
    deps = RuntimeDeps(provider=provider, decision_model=dm)

    events = _drain(
        _runtime().run(
            "一句话",
            role="teacher",
            ctx=_ctx(),
            deps=deps,
            business="data_a",
            allow_reroute=True,
        )
    )

    assert _FABRICATED not in _all_text(events), "无据正文不得出现在任何事件里"
    assert [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE] == [
        _HANDOVER_ANSWER
    ]
    # 交接在事件轨上显式可见（routing 思考帧），不是悄悄换的
    assert len(_handovers(events)) == 1
    assert "讲解业务" in _handovers(events)[0]
    assert dm.calls == 1


def test_reroute_target_excludes_the_business_that_failed():
    """候选集里不能有刚失败的那个业务——否则「换人」等于原样再来一遍。"""
    dm = _StubDecisionModel(DecisionResult(choice="plain", prob=0.9))
    seen: list[list[str]] = []

    class _Spy(_StubDecisionModel):
        async def decide(self, *, state, options):  # noqa: ANN001
            seen.append([o.key for o in options])
            return await super().decide(state=state, options=options)

    deps = RuntimeDeps(provider=_AnswersWithoutTools(), decision_model=_Spy(dm._result))
    _drain(
        _runtime().run(
            "一句话",
            role="teacher",
            ctx=_ctx(),
            deps=deps,
            business="data_a",
            allow_reroute=True,
        )
    )

    assert seen == [["plain"]], "重路由的候选必须已排除 data_a"


# ───────────────────── 换不出：维持原硬失败，不猜 ─────────────────────


def test_reroute_falls_back_to_hard_failure_when_model_silent():
    """决策模型没回 → 不猜，维持 ADR-0033 的原文。"""
    deps = RuntimeDeps(provider=_AnswersWithoutTools(), decision_model=_StubDecisionModel(None))

    events = _drain(
        _runtime().run(
            "一句话",
            role="teacher",
            ctx=_ctx(),
            deps=deps,
            business="data_a",
            allow_reroute=True,
        )
    )

    assert [ev.code for ev in _errors(events)] == ["TOOL_UNSUPPORTED"]
    assert "缺少数据支撑" in (_errors(events)[0].message or "")
    assert _handovers(events) == []
    assert _FABRICATED not in _all_text(events)


def test_reroute_falls_back_when_target_below_gate():
    """决策模型回了但分数不够 → 同 ADR-0107，过不了门控就等于没决策。

    这条是 B 类（模型不会原生 FC）的保护：真问题是「换模型」，而它在被排除后
    拿不到高分，于是仍是原提示语；不会被换成一个同样答非所问的业务。
    """
    deps = RuntimeDeps(
        provider=_AnswersWithoutTools(),
        decision_model=_StubDecisionModel(DecisionResult(choice="plain", prob=0.2)),
    )

    events = _drain(
        _runtime().run(
            "一句话",
            role="teacher",
            ctx=_ctx(),
            deps=deps,
            business="data_a",
            allow_reroute=True,
        )
    )

    assert [ev.code for ev in _errors(events)] == ["TOOL_UNSUPPORTED"]
    assert _handovers(events) == []


def test_reroute_is_off_unless_the_caller_asks_for_it():
    """``run`` 默认不重路由：不经 ``signal`` 路径的调用方不受新行为影响。"""
    dm = _StubDecisionModel(DecisionResult(choice="plain", prob=0.9))
    deps = RuntimeDeps(provider=_AnswersWithoutTools(), decision_model=dm)

    events = _drain(
        _runtime().run("一句话", role="teacher", ctx=_ctx(), deps=deps, business="data_a")
    )

    assert [ev.code for ev in _errors(events)] == ["TOOL_UNSUPPORTED"]
    assert dm.calls == 0, "未开重路由时不得去问决策模型"


# ───────────────────── 至多一次 ─────────────────────


def test_reroute_happens_at_most_once():
    """接手的业务同样无据 → 直接收原硬失败，不再换第三个。

    「至多一次」是本设计的循环闸：没有它，两个互相看不上的业务能把一条消息
    在彼此之间弹到轮次上限。
    """
    other = _as_business(_DataAgent, "data_b", "另一个数据业务")
    rt = _runtime(
        {
            "data_b": SubAgentManifest(
                business="data_b",
                name="另一个数据业务",
                description="也必须有据",
                roles=["teacher"],
                priority=9,
                agent_cls=other,
            )
        }
    )
    dm = _StubDecisionModel(DecisionResult(choice="data_b", prob=0.9))
    provider = _AnswersWithoutTools()
    deps = RuntimeDeps(provider=provider, decision_model=dm)

    events = _drain(
        rt.run(
            "一句话",
            role="teacher",
            ctx=_ctx(),
            deps=deps,
            business="data_a",
            allow_reroute=True,
        )
    )

    assert [ev.code for ev in _errors(events)] == ["TOOL_UNSUPPORTED"]
    assert dm.calls == 1, "重路由只问一次"
    assert provider.requests == 2, "两个业务各问一次，没有第三次"


# ───────────────────── 结构化路径不得被改判 ─────────────────────


def test_structured_path_is_never_rerouted():
    """结构化出题自带 business（规格即意图），不得被改判到别处。

    与聊天路径的区别：那条路径的 business 是路由算出来的，算错了才谈得上改判。
    """
    dm = _StubDecisionModel(DecisionResult(choice="plain", prob=0.9))
    provider = _AnswersWithoutTools()
    deps = RuntimeDeps(provider=provider, decision_model=dm)

    events = _drain(
        _runtime().invoke_subagent(
            "一句话",
            role="teacher",
            ctx=_ctx(),
            deps=deps,
            business="data_a",
        )
    )

    assert [ev.code for ev in _errors(events)] == ["TOOL_UNSUPPORTED"]
    assert dm.calls == 0, "结构化路径不重路由"
    assert _handovers(events) == []
    assert _FABRICATED not in _all_text(events)


# ───────────────────── 生产拓扑端到端（真实 manifest / 真实执行体） ─────────────────────


def test_production_topology_hands_tasks_over_to_tutor():
    """真实清单 + 真实执行体：tasks 无据 → 决策模型点名 tutor → 讲解真的流出来。

    前面的用例都用最小替身清单，证明的是**机制**；这条证明的是**接线**——
    ``TasksSubAgent.requires_tool_data`` 与 ``TutorSubAgent`` 的接手确实串在同一条
    流上，而不是只在一张人造清单里成立。
    """
    rt = AgentRuntime.discover()
    dm = _StubDecisionModel(DecisionResult(choice="tutor", prob=0.9))
    provider = FakeLLMProvider(tool_script=[], tool_text=_FABRICATED)
    deps = RuntimeDeps(provider=provider, decision_model=dm)

    events = _drain(
        rt.run(
            "23+45 怎么算",
            role="teacher",
            ctx=_ctx(),
            deps=deps,
            business="tasks",
            allow_reroute=True,
        )
    )

    assert _FABRICATED not in _all_text(events), "无据正文不得出现在任何事件里"
    # 接手方真的开口了（不比对替身的固定文案，免得替身改文案时本文件跟着红）
    answers = [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE]
    assert len(answers) == 1 and answers[0].strip()
    assert "伴学答疑" in _handovers(events)[0]
    assert dm.calls == 1


def test_production_topology_keeps_hard_failure_without_a_place_to_go():
    """生产拓扑下决策模型换不出落点 → 维持 ADR-0033 原文（B 类：真问题是换模型）。"""
    rt = AgentRuntime.discover()
    deps = RuntimeDeps(
        provider=FakeLLMProvider(tool_script=[], tool_text=_FABRICATED),
        decision_model=_StubDecisionModel(None),
    )

    events = _drain(
        rt.run(
            "小明最近错题多吗",
            role="teacher",
            ctx=_ctx(),
            deps=deps,
            business="tasks",
            allow_reroute=True,
        )
    )

    assert [ev.code for ev in _errors(events)] == ["TOOL_UNSUPPORTED"]
    assert "缺少数据支撑" in (_errors(events)[0].message or "")
    assert _FABRICATED not in _all_text(events)


def test_chat_path_reroutes_while_structured_does_not():
    """同一条 ``invoke_subagent``：带 signal 走改判，带 business 不走。

    端到端形态（与生产聊天路径一致）：决策模型先把这句话判给 ``data_a``（判错了），
    data_a 无据 → 排除自己再问一次 → 判给 ``plain`` → 讲业务把话接过去。
    """

    class _Sequenced(_StubDecisionModel):
        def __init__(self, results: list[DecisionResult]) -> None:
            super().__init__(None)
            self._results = list(results)

        async def decide(self, *, state, options):  # noqa: ANN001
            self.calls += 1
            return self._results.pop(0) if self._results else None

    dm = _Sequenced(
        [DecisionResult(choice="data_a", prob=0.9), DecisionResult(choice="plain", prob=0.9)]
    )
    deps = RuntimeDeps(provider=_AnswersWithoutTools(), decision_model=dm)

    events = _drain(
        _runtime().invoke_subagent(
            "23+45 怎么算", role="teacher", ctx=_ctx(), deps=deps, signal="23+45 怎么算"
        )
    )

    assert _FABRICATED not in _all_text(events)
    assert [ev.text for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE] == [
        _HANDOVER_ANSWER
    ]
    assert dm.calls == 2  # 首路由 + 重路由各一次
