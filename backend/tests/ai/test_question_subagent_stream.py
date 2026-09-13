"""出题 SubAgent 事件流单测：验证 STEP / THINKING / DATA 帧确实被产出。

回归背景：此前 ``QuestionSubAgent.run`` 每题一次性调用 ``generate_question``，
整条流只有 TOOL_CALL / DATA / TOOL_RESULT / ASSISTANT_MESSAGE，前端无从实时渲染
（``liveReasoning`` 恒空、``liveIndex`` 恒 -1 → 内联推理区永不显示）。

ADR-0028：语义事件经 ``translate_stream`` 转帧，**推理增量会按字符攒批**，
因此 THINKING 帧数少于语义事件数（同一次出题从数百帧降到数十帧）。
"""
from __future__ import annotations

import asyncio
from dataclasses import asdict

from agent_core.ports import LLMProvider, StructuredDone, TextDelta
from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_STEP,
    EVENT_THINKING,
    EVENT_TOOL_CALL,
    EVENT_TOOL_RESULT,
)
from agent_core.subagent import SubAgentContext
from app.ai.subagents.question.agent import QuestionSubAgent
from app.domain.provider import GeneratedQuestion

_Q = GeneratedQuestion(
    subject="数学",
    grade=3,
    knowledge_point="分数",
    qtype="choice",
    stem="1/2 + 1/2 = ?",
    options=["1", "2", "3", "4"],
    answer="A",
    explanation="同分母相加",
    difficulty="medium",
)


class _FakeProvider(LLMProvider):
    """按「每次出题产出的事件序列」构造的假 provider（消息级 stream）。"""

    def __init__(self, *, fail: bool = False) -> None:
        self._fail = fail

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if schema is not None:
            if self._fail:
                yield TextDelta(delta="想错了")
                return
            yield TextDelta(delta="先确认分母相同，")
            yield TextDelta(delta="再让分子相加。")
            yield StructuredDone(data=asdict(_Q))
            return
        yield TextDelta(delta="这是讲解")


class _ScriptedProvider(LLMProvider):
    """按「第几次调用成功与否」编排的假 provider（模拟逐题串行出题的部分失败）。"""

    def __init__(self, *, fail_at: set[int]) -> None:
        self._fail_at = fail_at
        self.calls = 0

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        self.calls += 1
        if self.calls in self._fail_at:
            yield TextDelta(delta="想错了")
            return
        yield TextDelta(delta="先确认分母相同，")
        yield StructuredDone(data=asdict(_Q))


def _run(message: str, *, fail: bool = False):
    agent = QuestionSubAgent(provider=_FakeProvider(fail=fail), retriever=None)
    ctx = SubAgentContext(role="parent", message=message)

    async def _go():
        return [ev async for ev in agent.run(message, ctx)]

    return asyncio.run(_go())


def _run_specs(specs: list[dict], *, fail_at: set[int]):
    """按结构化 specs 出题（ADR-0034），可指定第几次模型调用失败。"""
    agent = QuestionSubAgent(provider=_ScriptedProvider(fail_at=fail_at), retriever=None)
    ctx = SubAgentContext(role="parent", message="", extra={"specs": specs})

    async def _go():
        return [ev async for ev in agent.run("", ctx)]

    return asyncio.run(_go())


def _spec(subject: str, **kw) -> dict:
    base = {
        "subject": subject, "grade": 3, "knowledge_point": "分数",
        "qtype": "choice", "difficulty": "medium", "count": 1,
    }
    base.update(kw)
    return base


def test_emits_step_thinking_and_data_per_question():
    events = _run("帮我出2道三年级数学选择题，关于分数")

    types = [e.eventType for e in events]
    assert EVENT_TOOL_CALL in types
    # 每题一个进度锚点：2 题 → 2 个 STEP
    assert types.count(EVENT_STEP) == 2
    # 每题 2 个推理增量，攒批（15 字 < 阈值）后合并为 1 帧 → 共 2 个 THINKING
    assert types.count(EVENT_THINKING) == 2
    assert types.count(EVENT_DATA) == 2
    assert EVENT_TOOL_RESULT in types
    assert EVENT_ASSISTANT_MESSAGE in types

    # 顺序：STEP 必须早于该题的 THINKING / DATA（前端据此展开内联区）
    assert types.index(EVENT_STEP) < types.index(EVENT_THINKING)
    assert types.index(EVENT_THINKING) < types.index(EVENT_DATA)


def test_thinking_frames_carry_no_business_extra():
    """推理帧不得带 extra.business，否则会被前端当作路由帧过滤掉。"""
    events = _run("帮我出1道三年级数学选择题")
    thinkings = [e for e in events if e.eventType == EVENT_THINKING]
    assert thinkings
    for ev in thinkings:
        assert not (ev.extra or {}).get("business")


def test_data_payload_carries_reasoning():
    events = _run("帮我出1道三年级数学选择题")
    data = [e for e in events if e.eventType == EVENT_DATA][0]
    assert data.data["type"] == "question"
    assert data.data["result"]["reasoning"] == "先确认分母相同，再让分子相加。"
    assert data.data["result"]["stem"] == "1/2 + 1/2 = ?"


def test_step_label_readable():
    events = _run("帮我出1道三年级数学选择题，关于分数")
    step = [e for e in events if e.eventType == EVENT_STEP][0]
    assert "数学" in (step.label or "")
    assert step.status == "running"


def test_failed_question_emits_error_step():
    """解析/闸门失败必须显式成 status=error 的 STEP，不得静默跳过。"""
    events = _run("帮我出1道三年级数学选择题", fail=True)
    steps = [e for e in events if e.eventType == EVENT_STEP]
    error_steps = [s for s in steps if s.status == "error"]
    assert [s.label for s in error_steps] == ["模型未返回结构化题卡"]
    assert [e.eventType for e in events].count(EVENT_DATA) == 0


def test_partial_failure_reports_shortfall_in_tool_result():
    """多学科出题「某一科失败」必须在 TOOL_RESULT 里暴露计数，不得静默少题。

    回归背景：数学+语文各 1 题，语文那次模型调用失败时，前端把 STEP(status=error)
    当普通进度吞掉，流结束后照常落库 → 家长拿到只有数学的残缺任务且无任何提示。
    """
    events = _run_specs([_spec("数学"), _spec("语文")], fail_at={2})

    assert [e.eventType for e in events].count(EVENT_DATA) == 1
    result = [e for e in events if e.eventType == EVENT_TOOL_RESULT][0].result
    assert result == {
        "count": 1,
        "requested": 2,
        "failed": 1,
        "fail_reason": "模型未返回结构化题卡",
    }


def test_partial_failure_message_states_shortfall():
    """部分成功时收尾文案必须报「应出 / 实出」与失败原因。"""
    events = _run_specs([_spec("数学"), _spec("语文")], fail_at={2})
    text = [e for e in events if e.eventType == EVENT_ASSISTANT_MESSAGE][0].text
    assert "应出 2 题" in text
    assert "实出 1 题" in text
    assert "模型未返回结构化题卡" in text


def test_multi_subject_success_message_lists_all_subjects():
    """多学科全成功时不得只报第一科的学科名（旧实现会说「已生成 2 道数学题」）。"""
    events = _run_specs([_spec("数学"), _spec("语文")], fail_at=set())
    text = [e for e in events if e.eventType == EVENT_ASSISTANT_MESSAGE][0].text
    assert "已生成 2 道题" in text
    assert "数学 1 道" in text
    assert "语文 1 道" in text
