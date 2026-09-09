"""Agent Runtime 包（ADR-0024 / 0025 / 0026）。

统一承接「自由文本 → 意图识别 → SubAgent 派发 → 事件流 → 会话持久化」全流程；
对外仅暴露 ``POST /api/v1/assistant/chat``（见 app/api/routes/assistant.py）。
"""
from __future__ import annotations

from app.ai.runtime.manifest import SubAgentManifest, discover_subagent_manifests
from app.ai.runtime.runtime import AgentRuntime, RouteDecision

__all__ = ["AgentRuntime", "RouteDecision", "SubAgentManifest", "discover_subagent_manifests"]
