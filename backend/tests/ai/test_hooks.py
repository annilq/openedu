"""扩展钩子（extension seam，架构评审 P2）单测。

验证：
1. ``Hooks`` 基类三个方法默认零行为（原样返回）。
2. ``run_with_tools`` 在 before_turn / after_tool / rewrite_messages 三个固定点调用钩子，
   且钩子改写的结果确实进入事件流（如 TOOL_RESULT 载荷被 after_tool 改写）。
3. ``hooks=None`` 时完全不触发、行为与无钩子一致。
4. ``AgentRuntime.run`` 把 ``RuntimeDeps.hooks`` 透传到 ``run_with_tools``。
"""
import asyncio
from typing import Any, AsyncIterator

from agent_core.ports import Hooks, RuntimeDeps
from agent_core.protocol import EVENT_ASSISTANT_MESSAGE, EVENT_TOOL_RESULT
from agent_core.registry import SubAgentManifest
from agent_core.runtime import AgentRuntime
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools
from agent_core.tools import ToolSpec
from tests.utils.fake_provider import FakeLLMProvider


class _EchoAgent(BaseSubAgent):
    """测试用最小工具 subagent：声明一个 echo 工具，供钩子介入 tool loop。"""

    business = "hook_echo"

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        self.tools = [
            ToolSpec(
                name="echo",
                description="echo tool",
                schema={"type": "object"},
                handler=self._echo,
            )
        ]

    async def _echo(self, args, *, ctx=None, session=None) -> dict:
        return {"echo": args.get("text", "")}

    async def run(self, message, ctx, *, session=None) -> AsyncIterator[Any]:
        # 工具循环（run_with_tools）驱动本 subagent，run 不被调用；保留以满足抽象契约。
        # ``if False`` 分支永不进入，仅使本方法成为合法的 async generator。
        if False:
            yield


class _RecordingHooks(Hooks):
    """记录三个固定点的调用，并做可控改写。"""

    def __init__(self) -> None:
        self.before_turns: list[tuple] = []
        self.after_tools: list[tuple] = []
        self.rewrite_calls: list[list[dict]] = []

    async def before_turn(self, *, turn, system, prompt, history):
        out_system = system + "\n[hook: tenant=A]"
        # 记录 (turn, 入参 system, 返回 system, prompt, history)，便于断言改写生效
        self.before_turns.append((turn, system, out_system, prompt, history))
        return out_system, prompt, history

    async def after_tool(self, *, name, args, result, tool_call_id):
        self.after_tools.append((name, args, result, tool_call_id))
        if isinstance(result, dict):
            return {**result, "hooked": True}
        return result

    async def rewrite_messages(self, *, messages):
        self.rewrite_calls.append(messages)
        return messages


async def _collect(it: AsyncIterator[Any]) -> list:
    return [ev async for ev in it]


def _agent(provider: FakeLLMProvider) -> _EchoAgent:
    return _EchoAgent(provider=provider)


# ── 1. 基类零行为 ────────────────────────────────────────────────────────
def test_hooks_base_is_noop():
    h = Hooks()
    s, p, hist = asyncio.run(
        h.before_turn(turn=0, system="sys", prompt="pr", history=[{"role": "user", "content": "x"}])
    )
    assert (s, p) == ("sys", "pr") and hist == [{"role": "user", "content": "x"}]
    assert asyncio.run(h.after_tool(name="t", args={}, result={"a": 1}, tool_call_id="c")) == {"a": 1}
    assert asyncio.run(h.rewrite_messages(messages=[1, 2])) == [1, 2]


# ── 2. 三个固定点都被触发，且改写进入事件流 ─────────────────────────────
def test_run_with_tools_invokes_hooks():
    provider = FakeLLMProvider(tool_script=[("echo", {"text": "hi"})])
    hooks = _RecordingHooks()
    events = asyncio.run(_collect(run_with_tools(_agent(provider), "hi", SubAgentContext(), hooks=hooks)))

    # 两轮（首轮工具调用、次轮收尾）→ 两个固定点各触发两次
    assert len(hooks.before_turns) == 2
    assert hooks.before_turns[0][0] == 0
    assert "[hook: tenant=A]" in hooks.before_turns[0][2]  # 返回的 system 被改写
    assert len(hooks.after_tools) == 1
    assert hooks.after_tools[0][0] == "echo"
    assert len(hooks.rewrite_calls) >= 2

    # after_tool 改写结果确实进入 TOOL_RESULT 帧
    tr = [ev for ev in events if ev.eventType == EVENT_TOOL_RESULT]
    assert tr and tr[0].result.get("hooked") is True
    # 最终 ASSISTANT_MESSAGE 由 fake provider 收尾文本给出
    am = [ev for ev in events if ev.eventType == EVENT_ASSISTANT_MESSAGE]
    assert am and am[-1].text == provider.tool_text


# ── 3. hooks=None 时不触发、行为不变 ────────────────────────────────────
def test_run_with_tools_no_hooks_default():
    provider = FakeLLMProvider(tool_script=[("echo", {"text": "hi"})])
    events = asyncio.run(_collect(run_with_tools(_agent(provider), "hi", SubAgentContext())))
    tr = [ev for ev in events if ev.eventType == EVENT_TOOL_RESULT]
    assert tr and tr[0].result == {"echo": "hi"}  # 未被改写


# ── 4. AgentRuntime.run 透传 RuntimeDeps.hooks ──────────────────────────
def test_runtime_forwards_hooks():
    provider = FakeLLMProvider(tool_script=[("echo", {"text": "hi"})])
    manifest = SubAgentManifest(
        business="hook_echo", name="echo", roles=["parent", "child"], agent_cls=_EchoAgent
    )
    runtime = AgentRuntime({"hook_echo": manifest})
    hooks = _RecordingHooks()
    deps = RuntimeDeps(provider=provider, hooks=hooks)
    events = asyncio.run(
        _collect(runtime.run("hi", role="parent", ctx=SubAgentContext(), deps=deps, business="hook_echo"))
    )
    # 经 runtime.run → run_with_tools(hooks=deps.hooks)，钩子被触发
    assert len(hooks.after_tools) == 1
    assert hooks.after_tools[0][0] == "echo"
    tr = [ev for ev in events if ev.eventType == EVENT_TOOL_RESULT]
    assert tr and tr[0].result.get("hooked") is True


# ── 5. 即用型 TruncateOversizedToolResultHook（可选挂载组件） ───────────────
def test_truncate_hook_limits_tool_result():
    from app.features.assistant.hooks import TruncateOversizedToolResultHook

    hook = TruncateOversizedToolResultHook(max_chars=10)
    big = {"content": "x" * 100, "keep": 1}
    out = asyncio.run(hook.after_tool(name="t", args={}, result=big, tool_call_id="c"))
    assert out["keep"] == 1
    assert out["content"].endswith("…(已截断)")
    assert len(out["content"]) == 10 + len("…(已截断)")

    small = {"content": "short"}
    assert asyncio.run(hook.after_tool(name="t", args={}, result=small, tool_call_id="c")) == small

    non_str = {"content": 123}
    assert asyncio.run(hook.after_tool(name="t", args={}, result=non_str, tool_call_id="c")) == non_str

