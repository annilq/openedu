"""流式 Decoder：Genkit chunk → 归一化 ``Segment``（解析管线第 1 层）。

这是全项目**唯一**接触 genkit 流式类型的地方。上层（解析器 / SubAgent）只认
``Segment``，因此可脱离引擎、脱离 genkit 单测，换 LLM 框架只改本文件。

Genkit 0.10 Python 的 chunk 是 ``content: list[Part]``，``Part.root`` 按类型区分：

- ``ReasoningPart(reasoning=...)``：原生思维链（DeepSeek-R1 / o-series 等）。
  ``genkit_openai`` 已把 OpenAI 兼容的 ``reasoning_content`` 映射到此类型，
  所以**不需要**上层解析文本去猜「这段是不是思考」。
- ``TextPart(text=...)``：正式文本流。

这里用 duck-typing 读字段，避免把 genkit 的类型导入泄漏到上层。
"""
from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from dataclasses import dataclass
from enum import StrEnum


class SegmentKind(StrEnum):
    """流式片段的语义通道。"""

    REASONING = "reasoning"  # 原生思维链
    TEXT = "text"  # 正式文本


@dataclass(frozen=True)
class Segment:
    """归一化后的流式片段（与厂商无关）。"""

    kind: SegmentKind
    text: str


def _iter_segments(chunk: object) -> Iterator[Segment]:
    """从单个 genkit chunk 抽取片段（同步、纯函数）。"""
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
