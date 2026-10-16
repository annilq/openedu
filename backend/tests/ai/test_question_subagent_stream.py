"""出题 SubAgent 事件流单测：验证 STEP / THINKING / DATA 帧确实被产出。

回归背景：早期 ``QuestionSubAgent.run`` 每题一次性调用 ``generate_question``，
整条流只有 TOOL_CALL / DATA / TOOL_RESULT / ASSISTANT_MESSAGE，前端无从实时渲染
（``liveReasoning`` 恒空、``liveIndex`` 恒 -1 → 内联推理区永不显示）。

ADR-0028：语义事件经 ``translate_stream`` 转帧，**推理增量会按字符攒批**，
因此 THINKING 帧数少于语义事件数（同一次出题从数百帧降到数十帧）。

ADR-0097：出题降级为流式 tool——``run()`` 委托 ``run_with_tools``，provider 的
``tools`` 非空调用是 tool loop（首轮产 ``generate_questions`` ToolCall、回灌后
的收尾轮产正文），``schema`` 调用是出题生成本身。收尾话术改由模型据 ToolOutcome
计数生成，「应出 / 实出 / 失败」与多学科概览以回灌数据进入收尾轮可见的 history。
"""

from __future__ import annotations

import asyncio
import json
from dataclasses import asdict

from agent_core.ports import LLMProvider, StructuredDone, TextDelta, ToolCall
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
    """按「每次出题产出的事件序列」构造的假 provider（消息级 stream）。

    ADR-0097：tools 非空 = tool loop 调用。首轮（``tool_rounds == 1``）产出
    ``generate_questions`` ToolCall（args 留空——规格走 message 正则兜底路径）；
    回灌后的收尾轮记录 history（供断言「模型有据可依」）并产正文。
    """

    def __init__(self, *, fail: bool = False) -> None:
        self._fail = fail
        self.tool_rounds = 0
        self.wrapup_history: list | None = None

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if schema is not None:
            if self._fail:
                yield TextDelta(delta="想错了")
                return
            yield TextDelta(delta="先确认分母相同，")
            yield TextDelta(delta="再让分子相加。")
            yield StructuredDone(data=asdict(_Q))
            return
        if tools:
            self.tool_rounds += 1
            if self.tool_rounds == 1:
                yield ToolCall(name="generate_questions", args={})
                return
            self.wrapup_history = history
            yield TextDelta(delta="已生成。")
            return
        yield TextDelta(delta="这是讲解")


class _ScriptedProvider(LLMProvider):
    """按「第几次**出题调用**成功与否」编排的假 provider（模拟逐题串行的部分失败）。

    ``fail_at`` 只数 schema（出题）调用——tool loop 首轮与收尾轮不计入，
    与旧实现「第几题失败」的语义一致。
    """

    def __init__(self, *, fail_at: set[int]) -> None:
        self._fail_at = fail_at
        self.gen_calls = 0
        self.tool_rounds = 0
        self.wrapup_history: list | None = None

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if schema is not None:
            self.gen_calls += 1
            if self.gen_calls in self._fail_at:
                yield TextDelta(delta="想错了")
                return
            yield TextDelta(delta="先确认分母相同，")
            yield StructuredDone(data=asdict(_Q))
            return
        if tools:
            self.tool_rounds += 1
            if self.tool_rounds == 1:
                yield ToolCall(name="generate_questions", args={})
                return
            self.wrapup_history = history
            yield TextDelta(delta="已生成。")
            return
        yield TextDelta(delta="讲解")


def _run(message: str, *, fail: bool = False):
    provider = _FakeProvider(fail=fail)
    agent = QuestionSubAgent(provider=provider, retriever=None)
    ctx = SubAgentContext(role="teacher", message=message)

    async def _go():
        return [ev async for ev in agent.run(message, ctx)]

    return asyncio.run(_go()), provider


def _run_specs(specs: list[dict], *, fail_at: set[int]):
    """按结构化 specs 出题（ADR-0034），可指定第几次出题调用失败。"""
    provider = _ScriptedProvider(fail_at=fail_at)
    agent = QuestionSubAgent(provider=provider, retriever=None)
    ctx = SubAgentContext(role="teacher", message="", extra={"specs": specs})

    async def _go():
        return [ev async for ev in agent.run("", ctx)]

    return asyncio.run(_go()), provider


def _spec(subject: str, **kw) -> dict:
    base = {
        "subject": subject,
        "grade": 3,
        "knowledge_point": "分数",
        "qtype": "choice",
        "difficulty": "medium",
        "count": 1,
    }
    base.update(kw)
    return base


def _wrapup_tool_payload(provider) -> dict:
    """收尾轮可见历史里的最后一条 tool content（ToolOutcome.data 的 JSON）。"""
    assert provider.wrapup_history, "收尾轮必须拿到回灌的 tool 结果（模型据实汇报的依据）"
    return json.loads(provider.wrapup_history[-1]["content"])


def test_emits_step_thinking_and_data_per_question():
    events, _ = _run("帮我出2道三年级数学选择题，关于分数")

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
    events, _ = _run("帮我出1道三年级数学选择题")
    thinkings = [e for e in events if e.eventType == EVENT_THINKING]
    assert thinkings
    for ev in thinkings:
        assert not (ev.extra or {}).get("business")


def test_data_payload_carries_reasoning():
    events, _ = _run("帮我出1道三年级数学选择题")
    data = [e for e in events if e.eventType == EVENT_DATA][0]
    assert data.data["type"] == "question"
    assert data.data["result"]["reasoning"] == "先确认分母相同，再让分子相加。"
    assert data.data["result"]["stem"] == "1/2 + 1/2 = ?"


def test_step_label_readable():
    events, _ = _run("帮我出1道三年级数学选择题，关于分数")
    step = [e for e in events if e.eventType == EVENT_STEP][0]
    assert "数学" in (step.label or "")
    assert step.status == "running"


def test_failed_question_emits_error_step():
    """解析/闸门失败必须显式成 status=error 的 STEP，不得静默跳过。"""
    events, _ = _run("帮我出1道三年级数学选择题", fail=True)
    steps = [e for e in events if e.eventType == EVENT_STEP]
    error_steps = [s for s in steps if s.status == "error"]
    assert [s.label for s in error_steps] == ["模型未返回结构化题卡"]
    assert [e.eventType for e in events].count(EVENT_DATA) == 0


def test_partial_failure_reports_shortfall_in_tool_result():
    """多学科出题「某一科失败」必须在 TOOL_RESULT 里暴露计数，不得静默少题。

    回归背景：数学+语文各 1 题，语文那次模型调用失败时，前端把 STEP(status=error)
    当普通进度吞掉，流结束后照常落库 → 教师拿到只有数学的残缺任务且无任何提示。
    """
    events, _ = _run_specs([_spec("数学"), _spec("语文")], fail_at={2})

    assert [e.eventType for e in events].count(EVENT_DATA) == 1
    result = [e for e in events if e.eventType == EVENT_TOOL_RESULT][0].result
    assert result == {
        "count": 1,
        "requested": 2,
        "failed": 1,
        "fail_reason": "模型未返回结构化题卡",
        # ADR-0055 §13：RAG 溯源计数（无 RAG 时为 0）
        "referenced_materials": 0,
        "unindexed_materials": 0,
        # ADR-0097：多学科概览随回灌数据给收尾轮（防只报第一科）
        "subject_summary": "数学 1 道、语文 1 道",
    }


def test_partial_failure_counts_reach_wrapup_turn():
    """部分成功时，「应出 / 实出 / 失败」计数必须进入收尾轮可见的 history。

    ADR-0097 起收尾话术由模型生成（服务端不再吐固定文案），据实汇报的前提是
    计数随回灌数据到达收尾轮——本用例守住这个前提。
    """
    _events, provider = _run_specs([_spec("数学"), _spec("语文")], fail_at={2})
    payload = _wrapup_tool_payload(provider)
    assert payload["requested"] == 2
    assert payload["count"] == 1
    assert payload["failed"] == 1
    assert payload["fail_reason"] == "模型未返回结构化题卡"
    assert [e.eventType for e in _events][-1] == EVENT_ASSISTANT_MESSAGE


def test_multi_subject_summary_reaches_wrapup_turn():
    """多学科全成功时，各科概览必须随回灌数据到达收尾轮（防只报第一科）。"""
    _events, provider = _run_specs([_spec("数学"), _spec("语文")], fail_at=set())
    payload = _wrapup_tool_payload(provider)
    assert payload["count"] == 2
    assert payload["subject_summary"] == "数学 1 道、语文 1 道"
