"""语义事件 → AG-UI 帧的转换层（教育出题语义，属教育集成层，不进 agent_core）。

职责单一：把出题引擎层的语义事件（``ReasoningDelta`` / ``QuestionCard`` /
``QuestionFailed``）翻译成传输帧。SubAgent 只写
``async for frame in translate_stream(stream): yield frame``，不再内联 ``isinstance`` 分发。

加新语义事件 = 在 ``to_frames`` 的 ``match`` 里加一个分支，**不动 SSE 协议**。
事件类型超过 5 个再考虑换成注册表；现在上注册表是过度设计。

``translate_stream`` 顺带做**思维链帧聚合**：逐 token 下发会让一次出题产生数百个
THINKING 帧（每帧一次 SSE 写出 + 前端一次 setState）。这里按字符数攒批，遇其它帧
或流结束即冲刷，帧数降一个量级而打字机观感不变。
"""
from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from dataclasses import asdict

from agent_core.protocol import (
    EVENT_THINKING,
    AssistantEvent,
    data_event,
    step,
    thinking,
)
from app.domain.provider import (
    QuestionCard,
    QuestionFailed,
    QuestionStreamEvent,
    ReasoningDelta,
)

# 思维链攒批阈值（字符）。太小则聚合无意义，太大则首屏延迟。
_COALESCE_CHARS = 16


def to_frames(event: QuestionStreamEvent) -> Iterator[AssistantEvent]:
    """单个语义事件 → 零或多个传输帧。未知类型直接抛错（拒静默丢弃）。"""
    match event:
        case ReasoningDelta(delta=delta) if delta:
            yield thinking(delta)
        case QuestionCard(question=q, reasoning=reasoning):
            payload = asdict(q)
            if reasoning:
                payload["reasoning"] = reasoning
            yield data_event(payload, extra={"type": "question"})
        case QuestionFailed(reason=reason):
            yield step(reason, status="error")
        case _:
            raise TypeError(f"未注册的语义事件：{type(event).__name__}")


async def translate_stream(
    events: AsyncIterator[QuestionStreamEvent],
) -> AsyncIterator[AssistantEvent]:
    """转换 + 思维链聚合。语义事件流进，AG-UI 帧流出。"""
    buf = ""
    async for event in events:
        for frame in to_frames(event):
            if frame.eventType == EVENT_THINKING:
                buf += frame.text or ""
                if len(buf) >= _COALESCE_CHARS:
                    yield thinking(buf)
                    buf = ""
                continue
            if buf:
                yield thinking(buf)
                buf = ""
            yield frame
    if buf:
        yield thinking(buf)
