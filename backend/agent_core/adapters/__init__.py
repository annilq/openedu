"""agent_core 第一方适配器（adapters，可选扩展）。

六边形架构里，内核只定义**端口**（``agent_core.ports``）；本子包含「具体引擎」的实现——
把外部引擎接到端口上。与内核一样保持**零业务依赖**；可选启用，不污染内核契约。

当前提供：``genkit``（Genkit 引擎构造工厂 ``build_genkit_engine`` + ``LLMProvider`` 实现 + 流式解码）；
``laya``（Laya-multilingual 决策模型适配器，作路由主原语）。
"""
from __future__ import annotations

from agent_core.adapters.genkit import (
    GenkitEngine,
    GenkitLLMProvider,
    Segment,
    SegmentKind,
    build_genkit_engine,
    decode_stream,
)
from agent_core.adapters.laya import LayaDecisionModel, get_decision_model

__all__ = [
    "GenkitEngine",
    "GenkitLLMProvider",
    "Segment",
    "SegmentKind",
    "build_genkit_engine",
    "decode_stream",
    "LayaDecisionModel",
    "get_decision_model",
]
