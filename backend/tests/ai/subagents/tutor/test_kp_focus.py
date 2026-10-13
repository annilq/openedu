"""tutor 知识点聚焦注入测试（ADR-0080 / ai-prompts-hardening ticket 02）。

tutor 没有 ``initial_system`` 方法——聚焦段拼进传给 ``TutorService.aexplain_stream`` 的
``context``（与 ``tutor_system_prompt`` 安全锁物理分离）。本测试打桩
``aexplain_stream`` 抓取 ``context``，并打桩 ``resolve_interactive_scene`` 避免触发
场景库的 DB / LLM 路径，专注验证聚焦段注入。
"""
from __future__ import annotations

import asyncio
from unittest.mock import patch

from agent_core.subagent import SubAgentContext
from app.ai.subagents.tutor import TutorSubAgent
from app.domain.tutor import TutorStreamChunk
from tests.utils.fake_provider import FakeLLMProvider


def _capture_context():
    captured: dict = {}

    async def _fake_stream(self, **kwargs):
        captured.update(kwargs)
        yield TutorStreamChunk(done=True, answer="ok")

    return captured, _fake_stream


def test_tutor_injects_kp_focus_segment():
    captured, fake_stream = _capture_context()
    agent = TutorSubAgent(provider=FakeLLMProvider())
    ctx = SubAgentContext(
        role="student",
        extra={"knowledge_point": {"subject": "数学", "grade": 5, "semester": "上学期", "name": "轴对称"}},
    )

    async def _go():
        return [ev async for ev in agent.run("什么是轴对称", ctx)]

    with patch(
        "app.ai.subagents.tutor.agent.resolve_interactive_scene", return_value=None
    ), patch("app.domain.tutor.TutorService.aexplain_stream", fake_stream):
        asyncio.run(_go())

    context = captured.get("context", "")
    assert "【知识点聚焦】" in context
    assert "轴对称" in context
    assert "数学" in context and "5年级" in context


def test_tutor_no_kp_focus_without_extra():
    captured, fake_stream = _capture_context()
    agent = TutorSubAgent(provider=FakeLLMProvider())
    ctx = SubAgentContext(role="student", extra={})

    async def _go():
        return [ev async for ev in agent.run("什么是轴对称", ctx)]

    with patch(
        "app.ai.subagents.tutor.agent.resolve_interactive_scene", return_value=None
    ), patch("app.domain.tutor.TutorService.aexplain_stream", fake_stream):
        asyncio.run(_go())

    assert "【知识点聚焦】" not in captured.get("context", "")
