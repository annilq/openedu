"""agent_core genkit 适配器：把 Genkit 引擎接到 ``LLMProvider`` 端口。

本模块是「具体引擎实现」的落点（六边形架构的 adapter）：内核只在 ``agent_core.ports``
定义 ``LLMProvider`` 端口，这里提供其 Genkit 实现，并承担 genkit 特有的**流式解码**
（genkit chunk → 与厂商无关的 ``Segment``）。

**genkit 的唯一落点**：本模块是全工程唯一 ``import genkit`` 的地方——引擎构造
（``build_genkit_engine``，含 provider 前缀 / 缓存）与**工具消息映射**（``_build_tools`` /
``_build_messages``）都收敛在此，切换引擎只改本模块。genkit 采用**延迟导入**（仅在各函数体内），
因此未安装 genkit 时本模块仍可导入；``GenkitLLMProvider`` 以 duck-typing 调用
``genkit.generate_stream(...)``，不依赖 genkit 的类型。内核保持零第三方依赖。

业务专有能力（如教育的 ``tutor`` / ``grade_open``）**不在本模块**：内核与适配器都不认识
「年级 / 知识点 / 批改」，教育扩展留在 ``app`` 层。

**工具调用（ADR-0033）**：适配器不做编排，只做两件翻译——中性工具声明 → genkit 占位 ``Tool``；
中性 history ↔ genkit ``Message``/``Part``（含 ``ToolRequestPart`` / ``ToolResponsePart``）。
``return_tool_requests=True`` 保证 genkit **不自行执行**工具，模型的工具请求被译为中性
``ToolCall`` 交 runtime 执行。不支持时抛 ``ToolUnsupportedError``，**不静默降级**。
"""
from __future__ import annotations

import json
from collections.abc import AsyncIterator, Iterator
from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from agent_core.errors import ToolUnsupportedError
from agent_core.ports import (
    LLMProvider,
    StreamEvent,
    StructuredDone,
    TextDelta,
    ToolCall,
)


# ───────────────────────── 流式解码：genkit chunk → 中性 Segment ─────────────────────────
class SegmentKind(StrEnum):
    """流式片段的语义通道。"""

    REASONING = "reasoning"  # 原生思维链（DeepSeek-R1 / o-series 等）
    TEXT = "text"  # 正式文本


@dataclass(frozen=True)
class Segment:
    """归一化后的流式片段（与厂商无关）。"""

    kind: SegmentKind
    text: str


def _iter_segments(chunk: object) -> Iterator[Segment]:
    """从单个 genkit chunk 抽取片段（同步、纯函数）。

    genkit 的 chunk 为 ``content: list[Part]``，``Part.root`` 按类型区分
    （``ReasoningPart.reasoning`` / ``TextPart.text``）。这里用 duck-typing 读取，
    避免把 genkit 类型导入泄漏到上层。
    """
    for part in getattr(chunk, "content", None) or []:
        root = getattr(part, "root", part)
        reasoning = getattr(root, "reasoning", None)
        if reasoning:
            yield Segment(SegmentKind.REASONING, reasoning)
            continue
        text = getattr(root, "text", None)
        if text:
            yield Segment(SegmentKind.TEXT, text)


async def decode_stream(stream) -> AsyncIterator[Segment]:
    """把 genkit 的 chunk 流解码为 ``Segment`` 流。"""
    async for chunk in stream:
        for seg in _iter_segments(chunk):
            yield seg


def _chunk_text(chunk: object) -> str:
    """抽取 genkit 流式 chunk 的拼接文本（兼容 content/root.text 两种形态）。"""
    parts = getattr(chunk, "content", None) or []
    out: list[str] = []
    for part in parts:
        text = getattr(getattr(part, "root", part), "text", None)
        if text:
            out.append(text)
    return "".join(out)


def _as_dict(obj: Any) -> Any:
    """把结构化产出归一为 dict（兼容 dict / pydantic / 可迭代键值）。"""
    if obj is None:
        return None
    if isinstance(obj, dict):
        return obj
    if hasattr(obj, "model_dump"):
        return obj.model_dump()
    try:
        return dict(obj)
    except (TypeError, ValueError):
        return obj


# ───────────────────────── Genkit 引擎 + LLMProvider 实现 ─────────────────────────
@dataclass
class GenkitEngine:
    """genkit 运行时（适配器输入）：引擎实例 + 模型串（形如 ``openai/gpt-4o-mini``）。

    由业务层解析（读配置 / 解密密钥）后构造——适配器不认识配置来源。
    """

    genkit: Any
    model: str


# 引擎实例缓存：键为解析后的中性参数，避免重复构造（构造有成本）。
_ENGINE_CACHE: dict[tuple[str, str | None, str | None, str], Any] = {}


def _model_prefix(provider: str) -> str:
    """provider → genkit model 前缀（ollama / openai）。"""
    return "ollama" if provider == "ollama" else "openai"


def build_genkit_engine(
    *,
    provider: str,
    model_name: str,
    base_url: str | None = None,
    api_key: str | None = None,
) -> GenkitEngine:
    """构造（并按参数缓存）Genkit 引擎 + 模型串。

    全工程唯一 ``import genkit`` 处（延迟导入）：新增 provider / 切换引擎只动本函数，
    内核与业务层都不感知 genkit SDK。``base_url``（含 ollama 默认值）/ ``api_key``（解密后）
    由业务层解析后注入——适配器不认识配置来源。
    """
    key = (provider, base_url, api_key, model_name)
    engine = _ENGINE_CACHE.get(key)
    if engine is None:
        # 延迟导入：未安装 genkit 时本模块仍可 import（保持 import 期零第三方依赖）。
        from genkit import Genkit
        from genkit_ollama import Ollama
        from genkit_openai import OpenAI

        if provider == "ollama":
            engine = Genkit(
                plugins=[Ollama(server_address=base_url)], model=f"ollama/{model_name}"
            )
        else:  # openai_compat
            engine = Genkit(
                plugins=[OpenAI(api_key=api_key or "none", base_url=base_url)],
                model=f"openai/{model_name}",
            )
        _ENGINE_CACHE[key] = engine
    return GenkitEngine(genkit=engine, model=f"{_model_prefix(provider)}/{model_name}")


# ───────────────────────── 工具调用：中性 history ↔ genkit Message/Part 映射 ─────────────────────────
async def _placeholder_tool(**_: Any) -> None:
    """占位工具的函数体——**永不执行**。

    适配器用 ``return_tool_requests=True`` 让 genkit 只把模型的工具请求原样返回、不自行执行，
    故此处仅为满足 ``genkit.tool`` 对「async 函数」的形参要求。真被调用即说明配置错位
    （执行权应留在 ``agent_core`` runtime，ADR-0033）。
    """
    raise RuntimeError("占位工具不应被执行：工具执行权归 agent_core runtime（ADR-0033）")


def _build_tools(specs: list[Any]) -> list[Any]:
    """把中性工具声明（``{name, description, parameters}``）转为 genkit ``Tool`` 列表。

    ``genkit.tool`` 构造的是**临时工具**（不注册进 registry，由 ``register_tools`` 在调用期
    挂到子 registry），正合占位用途。声明非法时抛 ``ToolUnsupportedError``（ADR-0033：硬失败，
    不静默降级）。
    """
    from genkit import tool as define_ephemeral_tool

    built: list[Any] = []
    for spec in specs or []:
        if not isinstance(spec, dict) or not spec.get("name"):
            raise ToolUnsupportedError(f"工具声明非法（需 name/description/parameters 字典）：{spec!r}")
        parameters = spec.get("parameters") or {"type": "object", "properties": {}}
        built.append(
            define_ephemeral_tool(
                _placeholder_tool,
                name=str(spec["name"]),
                description=str(spec.get("description") or ""),
                input_schema=parameters,
            )
        )
    return built


def _build_messages(history: list[dict] | None) -> list[Any]:
    """把中性 ``history`` 映射为 genkit ``Message`` 列表（ADR-0033 决策 3）。

    支持三种条目（见 ``agent_core.ports.LLMProvider.stream`` 的 history 契约）：

    - ``{"role": "user"|"assistant", "content": str}`` → 纯文本消息；
    - ``{"role": "assistant", "content": str, "tool_calls": [{"name","args","ref"}]}``
      → 携带 ``ToolRequestPart`` 的模型消息（``ref`` 即 provider 侧 ``tool_call_id``）；
    - ``{"role": "tool", "name": str, "ref": str, "content": str}`` → 携带
      ``ToolResponsePart`` 的工具消息。

    后两者必须成对出现，否则 OpenAI 兼容端点会拒绝（tool 消息必须回应前一条 assistant 的
    ``tool_calls``）——这正是「回灌被忽略 → 死循环」之外，原先缺失的第二处映射。

    条目缺 ``ref`` 时（手写 history / 降级场景）自动 mint 并以**先进先出队列**配对，保证
    「请求 ref == 结果 ref」这一成对不变量恒成立。
    """
    from genkit import (
        Message,
        Part,
        Role,
        TextPart,
        ToolRequest,
        ToolRequestPart,
        ToolResponse,
        ToolResponsePart,
    )

    messages: list[Any] = []
    seq = 0
    pending: list[str] = []  # 尚未配对的工具调用 id（FIFO，供缺 ref 的结果条目认领）
    for entry in history or []:
        if not isinstance(entry, dict):
            raise ToolUnsupportedError(f"history 条目非法（需 dict）：{entry!r}")
        role = str(entry.get("role") or "").strip().lower()

        if role == "tool":
            if pending:
                ref = pending.pop(0)
            else:
                ref = f"call_{seq}"
                seq += 1
            messages.append(
                Message(
                    role=Role.TOOL,
                    content=[
                        Part(
                            root=ToolResponsePart(
                                tool_response=ToolResponse(
                                    name=str(entry.get("name") or ""),
                                    ref=ref,
                                    # content 已是 JSON 文本；原样交给 provider（避免 Python repr）
                                    output=entry.get("content") or "",
                                )
                            )
                        )
                    ],
                )
            )
            continue

        parts: list[Any] = []
        text = entry.get("content")
        if text:
            parts.append(Part(root=TextPart(text=str(text))))
        for call in entry.get("tool_calls") or []:
            if not isinstance(call, dict) or not call.get("name"):
                raise ToolUnsupportedError(f"tool_calls 条目非法（需 name/args）：{call!r}")
            ref = str(call["ref"]) if call.get("ref") else f"call_{seq}"
            if not call.get("ref"):
                seq += 1
            pending.append(ref)
            parts.append(
                Part(
                    root=ToolRequestPart(
                        tool_request=ToolRequest(
                            name=str(call["name"]),
                            input=call.get("args") or {},
                            ref=ref,
                        )
                    )
                )
            )
        if not parts:
            continue
        messages.append(Message(role=Role.MODEL if role == "assistant" else Role.USER, content=parts))
    return messages


def _coerce_args(raw: Any) -> dict[str, Any]:
    """把 provider 回传的工具入参归一为 dict（可能是 JSON 文本 / pydantic / 标量）。"""
    if raw is None:
        return {}
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            return {"_raw": raw}
        return parsed if isinstance(parsed, dict) else {"value": parsed}
    if hasattr(raw, "model_dump"):
        return raw.model_dump()
    return {"value": raw}


def _extract_tool_calls(response: Any) -> list[tuple[str, dict[str, Any]]]:
    """从 genkit 响应中抽取模型的工具请求（``message.content[i].root.tool_request``）。

    ``return_tool_requests=True`` 时 genkit 不执行工具，而是把 ``ToolRequest`` 原样放进响应消息；
    适配器在此把它译为中性 ``ToolCall``，执行权交给 runtime。
    """
    message = getattr(response, "message", None)
    calls: list[tuple[str, dict[str, Any]]] = []
    for part in getattr(message, "content", None) or []:
        root = getattr(part, "root", part)
        request = getattr(root, "tool_request", None)
        if request is None:
            continue
        name = getattr(request, "name", None)
        if not name:
            continue
        calls.append((str(name), _coerce_args(getattr(request, "input", None))))
    return calls


def _failure_reason(exc: BaseException) -> str:
    """把引擎异常压成一句可读原因（供 ``TOOL_UNSUPPORTED`` 帧展示）。"""
    detail = str(exc).strip() or exc.__class__.__name__
    return f"{exc.__class__.__name__}: {detail}"


def _response_text(response: Any) -> str:
    """取末帧响应里的正文（跳过工具请求 part / 原生思维链）。"""
    message = getattr(response, "message", None)
    chunks: list[str] = []
    for part in getattr(message, "content", None) or []:
        root = getattr(part, "root", part)
        if getattr(root, "tool_request", None):
            continue
        if getattr(root, "reasoning", None):
            continue
        text = getattr(root, "text", None)
        if isinstance(text, str) and text:
            chunks.append(text)
    return "".join(chunks)


class GenkitLLMProvider(LLMProvider):
    """``LLMProvider`` 的 Genkit 实现（消息级；三路：schema / tools / 纯文本）。

    - ``schema`` 给定 → 约束解码，产出 ``TextDelta``（推理）+ 末帧 ``StructuredDone(data=解析字典)``；
    - ``tools`` 给定 → **原生 function calling**：工具以占位 ``Tool`` 注册、``return_tool_requests=True``
      让 genkit 不自行执行，适配器把模型的工具请求译为 ``ToolCall`` 交 runtime 执行；``history`` 里的
      工具回灌映射为 ``ToolResponsePart`` 回传。引擎不支持 / 映射失败**一律抛
      ``ToolUnsupportedError``**，绝不静默降级为纯文本（ADR-0033——降级会让模型在没有数据的
      前提下编造业务结论）；
    - 两者皆无 → 纯文本，逐段 ``TextDelta``。
    """

    def __init__(self, engine: GenkitEngine) -> None:
        self._engine = engine

    async def stream(
        self,
        system: str,
        prompt: str,
        *,
        schema: Any | None = None,
        tools: list[Any] | None = None,
        history: list[dict] | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """消息级流式产出。"""
        engine = self._engine

        if schema is not None:
            sresp = engine.genkit.generate_stream(
                model=engine.model, system=system, prompt=prompt, output_schema=schema
            )
            async for seg in decode_stream(sresp.stream):
                if seg.kind is SegmentKind.REASONING:
                    yield TextDelta(delta=seg.text)
            resp = await sresp.response
            yield StructuredDone(data=_as_dict(getattr(resp, "output", None)))
            return

        if tools is not None:
            async for ev in self._stream_with_tools(engine, system, prompt, tools, history):
                yield ev
            return

        sresp = engine.genkit.generate_stream(model=engine.model, system=system, prompt=prompt)
        async for chunk in sresp.stream:
            text = _chunk_text(chunk)
            if text:
                yield TextDelta(delta=text)
        await sresp.response

    async def _stream_with_tools(
        self,
        engine: GenkitEngine,
        system: str,
        prompt: str,
        tools: list[Any],
        history: list[dict] | None,
    ) -> AsyncIterator[StreamEvent]:
        """原生 function calling 路径（ADR-0033 决策 2–4）。

        三步：① 把中性工具声明注册为**占位 Tool**；② 把中性 history 映射为 genkit ``Message``
        并随 ``return_tool_requests=True`` 一起请求（genkit 因此**不执行**工具，只回传请求）；
        ③ 从响应抽取工具请求译为 ``ToolCall``。

        任何环节失败（声明非法 / provider 不支持 / 映射或调用异常）都抛
        ``ToolUnsupportedError``——由 runtime 转 ``ERROR(TOOL_UNSUPPORTED)`` 并中止。
        """
        try:
            genkit_tools = _build_tools(tools)
            messages = _build_messages(history)
        except ToolUnsupportedError:
            raise
        except Exception as exc:  # noqa: BLE001 — 映射失败等价于「本引擎表达不了工具调用」
            raise ToolUnsupportedError(f"工具声明 / 历史映射失败：{_failure_reason(exc)}") from exc

        try:
            sresp = engine.genkit.generate_stream(
                model=engine.model,
                system=system,
                prompt=prompt,
                messages=messages,
                tools=genkit_tools,
                return_tool_requests=True,
            )
            streamed_text = False
            async for chunk in sresp.stream:
                for seg in _iter_segments(chunk):
                    if seg.kind is SegmentKind.TEXT:
                        streamed_text = True
                    yield TextDelta(delta=seg.text)
            resp = await sresp.response
        except Exception as exc:  # noqa: BLE001 — 硬失败：不降级、不假装查到了数据
            raise ToolUnsupportedError(_failure_reason(exc)) from exc

        # 兜底：未流式产出正文的 provider（只把正文放在末帧）也要把答复给出去，
        # 否则模型答了话而用户看到空回复。已流过正文则不重复（避免正文翻倍）。
        if not streamed_text:
            tail = _response_text(resp)
            if tail:
                yield TextDelta(delta=tail)

        for name, args in _extract_tool_calls(resp):
            yield ToolCall(name=name, args=args)
