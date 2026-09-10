"""genkit 适配器的工具路径契约（ADR-0033 第 2 阶段）。

第 1 阶段修好了内核的 tool loop 边界，但**真正让模型能调工具**的是适配器这一层。
本文件钉死三件此前完全缺失、且各自都能造成生产事故的事：

1. **history 必须被翻译**（而非丢弃）：中性 history → genkit ``Message``/``Part``，
   含 ToolRequest / ToolResponse part。丢弃 = 工具回灌丢失 = 模型反复重调同一工具。
2. **工具必须是合法 ``Tool``**：原实现把 ``{name, description, parameters}`` 字典直接传给
   ``generate_stream(tools=)``（形参是 ``Sequence[str | Tool]``）——类型非法，这正是它只能
   降级成纯文本的直接原因。现改为 ``genkit.tool(...)`` 构造的**占位 Tool**。
3. **失败必须硬抛**：原实现 ``except Exception: pass`` 后降级纯文本，等于允许模型在没拿到
   数据时编造业务结论（「你共有 3 个任务」）。现一律抛 ``ToolUnsupportedError``。

另有两条必须成立的性质：``return_tool_requests=True`` 让 genkit **不执行**工具（执行权留
runtime）；工具入参 JSON 文本须被解析成 dict。

全部离线：引擎与响应均为鸭子类型替身，**本文件不 import genkit**（沿用 ``test_genkit_adapter``
的约定，也保住「genkit 的唯一落点」分层不变量）。测试不得依赖真实模型（CI 红线）。
"""
from __future__ import annotations

import asyncio
import json
from types import SimpleNamespace

import pytest

from agent_core.adapters.genkit import (
    GenkitEngine,
    GenkitLLMProvider,
    _build_messages,
    _build_tools,
    _extract_tool_calls,
    _placeholder_tool,
)
from agent_core.errors import ToolUnsupportedError
from agent_core.ports import StructuredDone, TextDelta, ToolCall


# ───────────────────────── 假引擎（鸭子类型，不 import genkit） ─────────────────────────
def _chunk(text: str | None = None, reasoning: str | None = None):
    """genkit chunk：``content=[Part(root=TextPart|ReasoningPart)]``。"""
    root = SimpleNamespace(text=text, reasoning=reasoning, tool_request=None)
    return SimpleNamespace(content=[SimpleNamespace(root=root)])


def _tool_request_chunk(name: str, args):
    """流式工具请求分片（增量 part）：含 tool_request、无 text——不得被当成文本下发。"""
    root = SimpleNamespace(
        text=None, reasoning=None, tool_request=SimpleNamespace(name=name, input=args)
    )
    return SimpleNamespace(content=[SimpleNamespace(root=root)])


def _response(*, text: str = "", tool_requests=()):
    """genkit ModelResponse：``message.content[i].root.tool_request.{name,input}``。"""
    content = []
    if text:
        content.append(SimpleNamespace(root=SimpleNamespace(text=text, tool_request=None)))
    content.extend(
        SimpleNamespace(root=SimpleNamespace(text=None, tool_request=SimpleNamespace(name=n, input=a)))
        for n, a in tool_requests
    )
    return SimpleNamespace(message=SimpleNamespace(content=content))


async def _agen(items):
    for it in items:
        yield it


class _FakeGenkit:
    """记录 ``generate_stream`` 入参并返回预设响应；``boom`` 用于验证硬失败路径。"""

    def __init__(self, response=None, *, chunks=(), boom: Exception | None = None) -> None:
        self.response = response if response is not None else _response()
        self.chunks = list(chunks)
        self.boom = boom
        self.calls: list[dict] = []

    def generate_stream(self, **kwargs):
        self.calls.append(kwargs)
        if self.boom is not None:
            raise self.boom
        resp = self.response

        async def _done():
            return resp

        return SimpleNamespace(stream=_agen(self.chunks), response=_done())


def _provider(fake) -> GenkitLLMProvider:
    return GenkitLLMProvider(GenkitEngine(genkit=fake, model="openai/x"))


def _collect(provider, *, tools, history=None, prompt="查一下"):
    async def _run():
        return [ev async for ev in provider.stream("系统", prompt, tools=tools, history=history)]

    return asyncio.run(_run())


_SPEC = {
    "name": "list_children",
    "description": "列出孩子",
    "parameters": {"type": "object", "properties": {}, "required": []},
}


# ───────────────────────── ① 工具声明 → 合法 genkit Tool ─────────────────────────
def test_tool_specs_become_tool_objects_not_dicts():
    tools = _build_tools([_SPEC])

    assert len(tools) == 1
    assert not isinstance(tools[0], dict), "字典不是合法 tools 形参元素（原缺陷根因）"
    assert tools[0].name == "list_children"


def test_invalid_tool_declaration_is_hard_failure():
    with pytest.raises(ToolUnsupportedError):
        _build_tools(["not-a-dict"])


def test_placeholder_tool_body_never_runs_but_would_raise():
    """占位体存在只为满足 genkit 对 async 函数的形参要求；真跑即配置错位。"""
    with pytest.raises(RuntimeError, match="占位工具不应被执行"):
        asyncio.run(_placeholder_tool())


# ───────────────────────── ② history → genkit Message/Part ─────────────────────────
def test_history_maps_to_messages_with_tool_parts_and_matching_refs():
    messages = _build_messages(
        [
            {"role": "user", "content": "小明最近怎么样"},
            {
                "role": "assistant",
                "content": "",
                "tool_calls": [{"name": "list_children", "args": {}, "ref": "call_7"}],
            },
            {
                "role": "tool",
                "name": "list_children",
                "ref": "call_7",
                "content": json.dumps({"children": []}, ensure_ascii=False),
            },
        ]
    )

    assert [str(m.role) for m in messages] == ["user", "model", "tool"]
    request = messages[1].content[0].root
    response = messages[2].content[0].root
    assert type(request).__name__ == "ToolRequestPart"
    assert type(response).__name__ == "ToolResponsePart"
    # 关联 id 必须同值：OpenAI 要求 tool 消息的 tool_call_id 命中前一条 assistant 的 tool_calls
    assert request.tool_request.ref == response.tool_response.ref == "call_7"
    assert request.tool_request.name == "list_children"


def test_assistant_text_and_tool_calls_share_one_message():
    """带正文的助手轮 + 工具请求须在同一 Message 内（provider 侧即 content + tool_calls）。"""
    messages = _build_messages(
        [{"role": "assistant", "content": "我查一下", "tool_calls": [{"name": "a", "args": {"x": 1}}]}]
    )
    roots = [p.root for p in messages[0].content]
    assert [type(r).__name__ for r in roots] == ["TextPart", "ToolRequestPart"]
    assert roots[1].tool_request.input == {"x": 1}


def test_tool_message_output_is_json_text_not_python_repr():
    """工具结果必须原样以 JSON 文本回传（避免 dict 被 str() 成单引号 repr）。"""
    messages = _build_messages(
        [{"role": "tool", "name": "list_x", "ref": "c0", "content": '{"ok": true}'}]
    )
    assert messages[0].content[0].root.tool_response.output == '{"ok": true}'


def test_history_missing_ref_falls_back_to_a_matching_pair():
    """缺 ref 的 history（手写/降级场景）仍须能映射，且请求/结果自动配对。"""
    messages = _build_messages(
        [
            {"role": "assistant", "content": "", "tool_calls": [{"name": "a", "args": {}}]},
            {"role": "tool", "name": "a", "content": "{}"},
        ]
    )
    ref = messages[0].content[0].root.tool_request.ref
    assert ref
    assert ref == messages[1].content[0].root.tool_response.ref


def test_missing_refs_pair_fifo_for_multiple_calls():
    messages = _build_messages(
        [
            {
                "role": "assistant",
                "content": "",
                "tool_calls": [{"name": "a", "args": {}}, {"name": "b", "args": {}}],
            },
            {"role": "tool", "name": "a", "content": "{}"},
            {"role": "tool", "name": "b", "content": "{}"},
        ]
    )
    refs = [p.root.tool_request.ref for p in messages[0].content]
    assert len(set(refs)) == 2
    assert [m.content[0].root.tool_response.ref for m in messages[1:]] == refs


def test_invalid_history_entry_is_hard_failure():
    with pytest.raises(ToolUnsupportedError):
        _build_messages(["oops"])


def test_empty_history_maps_to_no_messages():
    assert _build_messages(None) == []
    assert _build_messages([]) == []


# ───────────────────────── ③ 请求构造 ─────────────────────────
def test_tools_path_requests_with_return_tool_requests_and_mapped_messages():
    fake = _FakeGenkit()
    _collect(_provider(fake), tools=[_SPEC], history=[{"role": "user", "content": "你好"}])

    call = fake.calls[0]
    assert call["return_tool_requests"] is True, "genkit 不执行工具，只回传请求（执行权留 runtime）"
    assert call["tools"] and not isinstance(call["tools"][0], dict)
    assert [str(m.role) for m in call["messages"]] == ["user"]
    assert call["prompt"] == "查一下"
    assert call["system"] == "系统"


def test_replay_after_tool_result_includes_request_and_response_messages():
    """第二轮请求必须带上「助手工具请求 + 工具结果」两条消息（否则端点直接拒绝）。"""
    fake = _FakeGenkit()
    history = [
        {"role": "user", "content": "查任务"},
        {"role": "assistant", "content": "", "tool_calls": [{"name": "a", "args": {}, "ref": "c1"}]},
        {"role": "tool", "name": "a", "ref": "c1", "content": "{}"},
    ]
    _collect(_provider(fake), tools=[_SPEC], history=history)

    assert [str(m.role) for m in fake.calls[0]["messages"]] == ["user", "model", "tool"]


def test_text_and_reasoning_chunks_are_streamed_as_text_delta():
    fake = _FakeGenkit(chunks=[_chunk(reasoning="先想"), _chunk(text="查到了")])
    events = _collect(_provider(fake), tools=[_SPEC])

    assert [e.delta for e in events if isinstance(e, TextDelta)] == ["先想", "查到了"]


def test_streamed_tool_request_chunks_do_not_leak_as_text():
    """流式工具请求分片无 text → 不得被当成文本下发（否则前端会出现乱码/空帧）。"""
    fake = _FakeGenkit(chunks=[_tool_request_chunk("a", {})])
    events = _collect(_provider(fake), tools=[_SPEC])

    assert [e for e in events if isinstance(e, TextDelta)] == []


def test_final_message_text_is_emitted_when_provider_did_not_stream():
    """不流式的 provider（正文只在末帧）也要出正文，否则模型答了话而用户看到空回复。"""
    fake = _FakeGenkit(_response(text="今天没有任务。"))
    events = _collect(_provider(fake), tools=[_SPEC])

    assert [e.delta for e in events if isinstance(e, TextDelta)] == ["今天没有任务。"]


def test_final_message_text_is_not_duplicated_when_already_streamed():
    """已流过正文时不得再补，否则答复翻倍。"""
    fake = _FakeGenkit(
        _response(text="查到了"), chunks=[_chunk(text="查到"), _chunk(text="了")]
    )
    events = _collect(_provider(fake), tools=[_SPEC])

    assert [e.delta for e in events if isinstance(e, TextDelta)] == ["查到", "了"]


# ───────────────────────── ④ 响应 → 中性 ToolCall ─────────────────────────
def test_tool_requests_become_tool_calls_with_parsed_args():
    fake = _FakeGenkit(_response(tool_requests=[("list_children", '{"grade": 3}')]))
    events = _collect(_provider(fake), tools=[_SPEC])

    calls = [e for e in events if isinstance(e, ToolCall)]
    assert len(calls) == 1
    assert calls[0].name == "list_children"
    assert calls[0].args == {"grade": 3}, "JSON 文本入参须被解析为 dict"


def test_multiple_tool_requests_in_one_turn_are_all_emitted():
    fake = _FakeGenkit(_response(tool_requests=[("a", {"x": 1}), ("b", {"y": 2})]))
    events = _collect(_provider(fake), tools=[_SPEC])

    calls = [e for e in events if isinstance(e, ToolCall)]
    assert [c.name for c in calls] == ["a", "b"]
    assert [c.args for c in calls] == [{"x": 1}, {"y": 2}]


def test_text_and_tool_request_in_same_response_both_surface():
    """模型先说话再请求工具：文本走 TextDelta、请求走 ToolCall，两者都不丢。

    （真实链路里正文是随 chunk 流式到达的，故替身把文本放在 chunks、把请求放在末帧响应。）
    """
    fake = _FakeGenkit(
        _response(text="我看看", tool_requests=[("a", {})]), chunks=[_chunk(text="我看看")]
    )
    events = _collect(_provider(fake), tools=[_SPEC])

    assert [e.delta for e in events if isinstance(e, TextDelta)] == ["我看看"]
    assert [e.name for e in events if isinstance(e, ToolCall)] == ["a"]


def test_no_tool_request_yields_no_tool_call():
    fake = _FakeGenkit(_response(text="今天没有任务。"))
    events = _collect(_provider(fake), tools=[_SPEC])

    assert [e for e in events if isinstance(e, ToolCall)] == []


def test_extract_tool_calls_tolerates_scalar_and_none_args():
    assert _extract_tool_calls(_response(tool_requests=[("t", None)])) == [("t", {})]
    assert _extract_tool_calls(_response(tool_requests=[("t", "not json")])) == [
        ("t", {"_raw": "not json"})
    ]
    assert _extract_tool_calls(_response(tool_requests=[("t", {"a": 1})])) == [("t", {"a": 1})]


def test_extract_tool_calls_survives_missing_message():
    assert _extract_tool_calls(SimpleNamespace(message=None)) == []
    assert _extract_tool_calls(SimpleNamespace()) == []


# ───────────────────────── ⑤ 硬失败：绝不静默降级 ─────────────────────────
def test_engine_failure_raises_tool_unsupported_instead_of_degrading():
    """原缺陷：``except: pass`` 后降级纯文本 → 模型可在没有数据时编造业务结论。"""
    fake = _FakeGenkit(boom=RuntimeError("model does not support tools"))

    with pytest.raises(ToolUnsupportedError, match="does not support tools"):
        _collect(_provider(fake), tools=[_SPEC])


def test_failure_after_partial_stream_still_raises():
    """已吐出部分文本也不能「吞掉异常改当纯文本答完」——必须硬失败。"""

    class _BoomStream:
        def generate_stream(self, **kwargs):
            async def _gen():
                yield _chunk(text="正在查")

                raise RuntimeError("connection reset")

            class _StreamResponse:
                stream = _gen()

                @property
                def response(self):
                    async def _done():
                        raise RuntimeError("connection reset")

                    return _done()

            return _StreamResponse()

    with pytest.raises(ToolUnsupportedError, match="connection reset"):
        _collect(_provider(_BoomStream()), tools=[_SPEC])


# ───────────────────────── ⑥ 回归护栏：schema 路不变 ─────────────────────────
def test_schema_path_is_unaffected():
    class _SchemaGenkit:
        def generate_stream(self, **kwargs):
            assert "output_schema" in kwargs

            async def _done():
                return SimpleNamespace(output={"stem": "题干"})

            return SimpleNamespace(stream=_agen([_chunk(reasoning="推")]), response=_done())

    async def _run_schema():
        return [
            ev
            async for ev in _provider(_SchemaGenkit()).stream("s", "p", schema={"type": "object"})
        ]

    events = asyncio.run(_run_schema())
    assert [e.delta for e in events if isinstance(e, TextDelta)] == ["推"]
    assert [e.data for e in events if isinstance(e, StructuredDone)] == [{"stem": "题干"}]
