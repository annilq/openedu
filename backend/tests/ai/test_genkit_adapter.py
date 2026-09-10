"""genkit 适配器契约单测（agent_core.adapters.genkit + app 侧委托）。

覆盖六边形 adapter 的接口：
1. ``decode_stream`` 把 genkit chunk 归一为 ``Segment``（Reasoning / Text 两通道）；
2. ``GenkitLLMProvider.stream`` 三路：schema / tools / 纯文本，及 tools 降级；
3. app 侧 ``GenkitProvider`` 把 ``EngineResolution`` 适配为 ``GenkitEngine`` 并委托。

全部使用假引擎（SimpleNamespace），**不打真实模型**。
"""
from __future__ import annotations

import asyncio
from types import SimpleNamespace

from agent_core.adapters.genkit import (
    GenkitEngine,
    GenkitLLMProvider,
    Segment,
    SegmentKind,
    decode_stream,
)
from agent_core.ports import StructuredDone, TextDelta


def _chunk(text: str | None = None, reasoning: str | None = None):
    """genkit chunk：content=[Part(root=TextPart|ReasoningPart)]。"""
    root = SimpleNamespace(text=text, reasoning=reasoning)
    return SimpleNamespace(content=[SimpleNamespace(root=root)])


async def _agen(items):
    for it in items:
        yield it


def _resp(chunks, output=None):
    class _Resp:
        def __init__(self) -> None:
            self.stream = _agen(chunks)

            async def _done():
                return SimpleNamespace(output=output)

            # 对齐 genkit ModelStreamResponse：response 是 awaitable，不是方法
            self.response = _done()

    return _Resp()


def _engine(chunks, output=None, *, raise_on_tools: bool = False) -> GenkitEngine:
    def _generate_stream(*, model=None, system=None, prompt=None, tools=None, **kwargs):
        if raise_on_tools and tools is not None:
            raise RuntimeError("tool calling 不被支持")
        return _resp(chunks, output=output)

    return GenkitEngine(genkit=SimpleNamespace(generate_stream=_generate_stream), model="openai/x")


def _run(engine: GenkitEngine, **kw):
    async def _collect():
        return [ev async for ev in GenkitLLMProvider(engine).stream("sys", "usr", **kw)]

    return asyncio.run(_collect())


def _deltas(events) -> str:
    return "".join(e.delta for e in events if isinstance(e, TextDelta))


# ───────────────────────── 1) decode_stream ─────────────────────────
def test_decode_stream_normalizes_both_channels():
    chunks = [_chunk(reasoning="先想"), _chunk(text="再答")]

    async def _collect():
        return [s async for s in decode_stream(_agen(chunks))]

    segs = asyncio.run(_collect())
    assert [(s.kind, s.text) for s in segs] == [
        (SegmentKind.REASONING, "先想"),
        (SegmentKind.TEXT, "再答"),
    ]


def test_decode_stream_skips_empty_parts():
    chunks = [_chunk(), _chunk(text="答"), SimpleNamespace(content=None)]

    async def _collect():
        return [s async for s in decode_stream(_agen(chunks))]

    segs = asyncio.run(_collect())
    assert [(s.kind, s.text) for s in segs] == [(SegmentKind.TEXT, "答")]
    assert all(isinstance(s, Segment) for s in segs)


# ───────────────────────── 2) GenkitLLMProvider 三路 ─────────────────────────
def test_schema_branch_streams_reasoning_then_structured_done():
    """schema 路：只把原生思维链发 TextDelta，末帧 StructuredDone 带解析产出。"""
    eng = _engine([_chunk(reasoning="推"), _chunk(text='{"a": 1}')], output={"a": 1})
    events = _run(eng, schema=object())

    assert [e.delta for e in events if isinstance(e, TextDelta)] == ["推"]
    assert [e.data for e in events if isinstance(e, StructuredDone)] == [{"a": 1}]


def test_text_branch_streams_only_text_chunks():
    """纯文本路：仅拼接 TextPart；ReasoningPart 不参与（无 schema → 不当推理下发）。"""
    eng = _engine([_chunk(text="答"), _chunk(reasoning="略")])
    events = _run(eng)

    assert _deltas(events) == "答"
    assert not any(isinstance(e, StructuredDone) for e in events)


def test_tools_branch_streams_text_deltas():
    eng = _engine([_chunk(text="你"), _chunk(text="好")])
    events = _run(eng, tools=[{"name": "t"}])

    assert _deltas(events) == "你好"


def test_tools_branch_degrades_to_text_on_error():
    """函数调用不被支持时降级为纯文本，不抛错、不中断流。"""
    eng = _engine([_chunk(text="降级")], raise_on_tools=True)
    events = _run(eng, tools=[{"name": "t"}])

    assert _deltas(events) == "降级"


# ───────────────────────── 3) app 侧委托接线 ─────────────────────────
def test_app_provider_delegates_to_adapter(monkeypatch):
    """GenkitProvider 把 EngineResolution 适配为 GenkitEngine 并委托适配器。"""
    import app.domain.genkit_provider as gp
    from app.ai.engine import EngineResolution

    fake = EngineResolution(
        genkit=SimpleNamespace(
            generate_stream=lambda **kw: _resp([_chunk(text="你好")], output=None)
        ),
        model="openai/x",
    )
    monkeypatch.setattr(gp, "resolve_engine", lambda: fake)

    async def _collect():
        return [ev async for ev in gp.GenkitProvider().stream("sys", "usr")]

    events = asyncio.run(_collect())
    assert _deltas(events) == "你好"


# ───────────────────────── 4) 引擎工厂（genkit SDK 构造的唯一落点） ─────────────────────────
def test_build_genkit_engine_openai_prefix_and_cache():
    """openai_compat → ``openai/`` 前缀；同参数第二次命中缓存（同一实例）。"""
    from agent_core.adapters.genkit import build_genkit_engine

    e1 = build_genkit_engine(provider="openai_compat", model_name="gpt-4o-mini", api_key="k")
    e2 = build_genkit_engine(provider="openai_compat", model_name="gpt-4o-mini", api_key="k")

    assert e1.model == "openai/gpt-4o-mini"
    assert e1.genkit is not None
    assert e1.genkit is e2.genkit


def test_build_genkit_engine_ollama_prefix():
    from agent_core.adapters.genkit import build_genkit_engine

    e = build_genkit_engine(
        provider="ollama", model_name="llama3", base_url="http://localhost:11434"
    )
    assert e.model == "ollama/llama3"
    assert e.genkit is not None


def _imported_modules(module, *, top_level_only: bool) -> set[str]:
    """模块真实 import 的模块名集合（AST 级，不受 docstring 中的字面量干扰）。"""
    import ast
    import inspect

    tree = ast.parse(inspect.getsource(module))
    nodes = tree.body if top_level_only else ast.walk(tree)
    mods: set[str] = set()
    for node in nodes:
        if isinstance(node, ast.Import):
            mods.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            mods.add(node.module.split(".")[0])
    return mods


def _genkit_imports(mods: set[str]) -> set[str]:
    return {m for m in mods if m == "genkit" or m.startswith("genkit_")}


def test_engine_module_has_no_genkit_import():
    """分层不变量：app/ai/engine.py 不再直接依赖 genkit SDK（构造已归适配器）。"""
    import app.ai.engine as engine_mod

    assert not _genkit_imports(_imported_modules(engine_mod, top_level_only=False))


def test_engine_adapter_imports_genkit_lazily():
    """适配器保持 import 期零第三方依赖：genkit 仅在工厂函数体内（非模块级）import。"""
    import agent_core.adapters.genkit as adapter_mod

    assert not _genkit_imports(_imported_modules(adapter_mod, top_level_only=True))
    assert _genkit_imports(_imported_modules(adapter_mod, top_level_only=False))
