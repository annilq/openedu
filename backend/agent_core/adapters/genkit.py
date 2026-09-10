"""agent_core genkit 适配器：把 Genkit 引擎接到 ``LLMProvider`` 端口。

本模块是「具体引擎实现」的落点（六边形架构的 adapter）：内核只在 ``agent_core.ports``
定义 ``LLMProvider`` 端口，这里提供其 Genkit 实现，并承担 genkit 特有的**流式解码**
（genkit chunk → 与厂商无关的 ``Segment``）。

**genkit 的唯一落点**：``build_genkit_engine`` 是全工程唯一 ``import genkit`` 的地方——
Genkit 实例的构造（以及 provider 前缀 / 缓存）都收敛在此，切换引擎只改本函数。genkit 采用
**延迟导入**（在工厂函数体内），因此未安装 genkit 时本模块仍可导入；``GenkitLLMProvider``
以 duck-typing 调用 ``genkit.generate_stream(...)``，不依赖 genkit 的类型。内核保持零第三方依赖。

业务专有能力（如教育的 ``tutor`` / ``grade_open``）**不在本模块**：内核与适配器都不认识
「年级 / 知识点 / 批改」，教育扩展留在 ``app`` 层。
"""
from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from agent_core.ports import LLMProvider, StreamEvent, StructuredDone, TextDelta


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


class GenkitLLMProvider(LLMProvider):
    """``LLMProvider`` 的 Genkit 实现（消息级；三路：schema / tools / 纯文本）。

    - ``schema`` 给定 → 约束解码，产出 ``TextDelta``（推理）+ 末帧 ``StructuredDone(data=解析字典)``；
    - ``tools`` 给定 → 尽力走函数调用（API 差异或异常时降级为纯文本，保证不崩）；
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
            # 尽力走函数调用；API 差异或异常时降级为纯文本，保证不崩。
            try:
                sresp = engine.genkit.generate_stream(
                    model=engine.model, system=system, prompt=prompt, tools=tools
                )
                async for chunk in sresp.stream:
                    text = _chunk_text(chunk)
                    if text:
                        yield TextDelta(delta=text)
                await sresp.response
                return
            except Exception:  # noqa: BLE001 — 降级保护
                pass

        sresp = engine.genkit.generate_stream(model=engine.model, system=system, prompt=prompt)
        async for chunk in sresp.stream:
            text = _chunk_text(chunk)
            if text:
                yield TextDelta(delta=text)
        await sresp.response
