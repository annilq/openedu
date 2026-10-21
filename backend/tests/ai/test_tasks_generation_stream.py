"""出题流式 tool 事件流单测：验证 STEP / THINKING / DATA 帧确实被产出。

回归背景：早期 ``QuestionSubAgent.run`` 每题一次性调用 ``generate_question``，
整条流只有 TOOL_CALL / DATA / TOOL_RESULT / ASSISTANT_MESSAGE，前端无从实时渲染
（``liveReasoning`` 恒空、``liveIndex`` 恒 -1 → 内联推理区永不显示）。

ADR-0028：语义事件经 ``translate_stream`` 转帧，**推理增量会按字符攒批**，
因此 THINKING 帧数少于语义事件数（同一次出题从数百帧降到数十帧）。

ADR-0097：出题降级为流式 tool——``run()`` 委托 ``run_with_tools``，provider 的
``tools`` 非空调用是 tool loop（首轮产 ``generate_questions`` ToolCall、回灌后
的收尾轮产正文），``schema`` 调用是出题生成本身。收尾话术改由模型据 ToolOutcome
计数生成，「应出 / 实出 / 失败」与多学科概览以回灌数据进入收尾轮可见的 history。

ADR-0098：question 域并入 tasks，本文件随迁改名（``TasksSubAgent`` 承载）。
"""

from __future__ import annotations

import asyncio
import json
import re
import uuid
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
from app.ai.subagents.tasks.agent import TasksSubAgent
from app.ai.subagents.tasks.generation.parsers import QuestionListSchema
from app.domain.provider import GeneratedQuestion
from app.domain.safety import SafetyVerdict

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


def _shaped(schema, prompt: str) -> dict:
    """按本次请求实际约束的 schema 组装产出：批量 schema 包一层数组。

    假 provider 若不跟着 schema 走，批量路径上就会拿到单个对象——那正是要防的
    「契约与解析器漂移」：真实 provider 返回什么由 output_schema 决定。

    数组里给几个元素照 prompt 里说的「出 N 道」来（真模型也是照这句话给的），
    这样「模型少给」的用例才能被显式编排出来。
    """
    payload = asdict(_Q)
    if schema is not QuestionListSchema:
        return payload
    m = re.search(r"出\s*(\d+)\s*道", prompt)
    return {"questions": [payload] * (int(m.group(1)) if m else 1)}


class _FakeProvider(LLMProvider):
    """按「每次出题产出的事件序列」构造的假 provider（消息级 stream）。

    ADR-0097：tools 非空 = tool loop 调用。首轮（``tool_rounds == 1``）产出
    ``generate_questions`` ToolCall（args 留空——规格走 message 正则兜底路径）；
    回灌后的收尾轮记录 history（供断言「模型有据可依」）并产正文。

    ADR-0108：批量 schema 时按数组出货（每组一次请求，组内 N 道逐题返回）。
    """

    def __init__(self, *, fail: bool = False) -> None:
        self._fail = fail
        self.tool_rounds = 0
        self.wrapup_history: list | None = None
        self.gen_calls = 0

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if schema is not None:
            self.gen_calls += 1
            if self._fail:
                yield TextDelta(delta="想错了")
                return
            yield TextDelta(delta="先确认分母相同，")
            yield TextDelta(delta="再让分子相加。")
            yield StructuredDone(data=_shaped(schema, prompt))
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
            yield StructuredDone(data=_shaped(schema, prompt))
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
    agent = TasksSubAgent(provider=provider, retriever=None)
    ctx = SubAgentContext(role="teacher", message=message)

    async def _go():
        return [ev async for ev in agent.run(message, ctx)]

    return asyncio.run(_go()), provider


def _run_specs(specs: list[dict], *, fail_at: set[int]):
    """按结构化 specs 出题（ADR-0034），可指定第几次出题调用失败。"""
    provider = _ScriptedProvider(fail_at=fail_at)
    agent = TasksSubAgent(provider=provider, retriever=None)
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
    events, provider = _run("帮我出2道三年级数学选择题，关于分数")

    types = [e.eventType for e in events]
    assert EVENT_TOOL_CALL in types
    # ADR-0108：同规格的 2 道并成一次请求 → 一个进度锚点（此前是每题一个）
    assert types.count(EVENT_STEP) == 1
    assert provider.gen_calls == 1
    # 2 个推理增量攒批（15 字 < 阈值）后合并为 1 帧
    assert types.count(EVENT_THINKING) == 1
    # 题卡仍是一题一卡：批量改的是请求数，不是卡片契约
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


# ── ADR-0108：批量出题（同规格一组一次请求） ─────────────────────────


class _BatchProvider(LLMProvider):
    """批量出题的假 provider：数组里给几道照 prompt 说的来。

    ``short`` 少给几道（模拟模型只出了一部分）；``unsafe_at`` 第几道题面不过闸。
    两者都是为了让「少题 / 部分不过闸」从隐性变成显式可断言。
    """

    def __init__(self, *, short: int = 0, unsafe_at: set[int] | None = None) -> None:
        self._short = short
        self._unsafe_at = unsafe_at or set()
        self.gen_calls = 0
        self.tool_rounds = 0
        self.wrapup_history: list | None = None

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if schema is not None:
            self.gen_calls += 1
            m = re.search(r"出\s*(\d+)\s*道", prompt)
            n = max(0, (int(m.group(1)) if m else 1) - self._short)
            questions = []
            for i in range(n):
                q = asdict(_Q)
                q["stem"] = f"第{i + 1}题：1/2 + 1/2 = ?"
                if i in self._unsafe_at:
                    q["stem"] = "BAD 题面"
                questions.append(q)
            if not questions:
                return  # 一道都没给 → 流水线应报「模型未返回结构化题卡」
            yield StructuredDone(
                data=(
                    {"questions": questions}
                    if schema is QuestionListSchema
                    else questions[0]
                )
            )
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


def _run_batch(specs: list[dict], **kw):
    provider = _BatchProvider(**kw)
    agent = TasksSubAgent(provider=provider, retriever=None)
    ctx = SubAgentContext(role="teacher", message="", extra={"specs": specs})

    async def _go():
        return [ev async for ev in agent.run("", ctx)]

    return asyncio.run(_go()), provider


def _cards_of(events) -> list[dict]:
    return [
        e.data["result"]
        for e in events
        if e.eventType == EVENT_DATA and e.data and e.data.get("type") == "question"
    ]


def test_same_spec_batch_uses_one_request():
    """同规格 N 道 → 一次请求（ADR-0108：此前是逐题 N 次）。"""
    events, provider = _run_batch([_spec("数学", count=3)])

    assert provider.gen_calls == 1
    cards = _cards_of(events)
    assert len(cards) == 3
    # 三张卡是三道题（逐题装配，不是同一张卡复制三份）
    assert [c["stem"] for c in cards] == [f"第{i}题：1/2 + 1/2 = ?" for i in (1, 2, 3)]


def test_multi_spec_uses_one_request_per_group():
    """多规格按规格分组，一组一次请求：规格不同就不该并进一次请求。"""
    events, provider = _run_batch([_spec("数学", count=2), _spec("语文", count=1)])

    assert provider.gen_calls == 2
    assert len(_cards_of(events)) == 3


def test_batch_progress_label_states_how_many():
    """批量进度锚点写明题数（前端据此显示「正在出 N 道」）。"""
    events, _ = _run_batch([_spec("数学", count=3)])
    steps = [e for e in events if e.eventType == EVENT_STEP]
    assert any("出 3 道" in (s.label or "") for s in steps)


def test_batch_shortfall_is_reported_not_silent():
    """模型少给：静默少题是最坏结果，必须有失败痕且进收尾轮计数。"""
    events, provider = _run_batch([_spec("数学", count=3)], short=1)

    assert len(_cards_of(events)) == 2
    error_steps = [
        s.label for s in events if s.eventType == EVENT_STEP and s.status == "error"
    ]
    assert error_steps == ["少出 1 道"]

    result = [e for e in events if e.eventType == EVENT_TOOL_RESULT][0].result
    assert result["requested"] == 3
    assert result["count"] == 2
    assert result["failed"] == 1


def test_batch_empty_questions_reports_not_silent():
    """数组为空（模型一道没给）→ 整批失败，不静默跳过。"""
    events, _ = _run_batch([_spec("数学", count=2)], short=2)

    assert _cards_of(events) == []
    error_steps = [
        s.label for s in events if s.eventType == EVENT_STEP and s.status == "error"
    ]
    assert error_steps == ["模型未返回结构化题卡"]


def test_batch_drops_only_the_unsafe_question(monkeypatch):
    """逐题闸门：一道不过闸只丢那一道，同批其它题照发（不连坐）。"""
    monkeypatch.setattr(
        "app.ai.subagents.tasks.generation.parsers.check_output",
        lambda text: SafetyVerdict(safe=("BAD" not in text), reason="测试"),
    )
    events, _ = _run_batch([_spec("数学", count=3)], unsafe_at={1})

    cards = _cards_of(events)
    assert len(cards) == 2
    assert all("BAD" not in c["stem"] for c in cards)
    # 少掉的那一道要留痕，收尾轮才说得清「应出 3 道、实出 2 道」
    result = [e for e in events if e.eventType == EVENT_TOOL_RESULT][0].result
    assert result["requested"] == 3
    assert result["count"] == 2
    assert result["failed"] == 1


# ── ADR-0102：流式题卡也要带图（选项盖章 + 交互讲解快照） ──────────────


class _FigureProvider(LLMProvider):
    """产出**带 figure_key** 的题卡（模拟模型按目录填身份键），其余同 _FakeProvider。"""

    def __init__(self) -> None:
        self.tool_rounds = 0

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if schema is not None:
            yield TextDelta(delta="按轴对称出一题。")
            yield StructuredDone(
                data={
                    **_question_with_figures(),
                }
            )
            return
        if tools:
            self.tool_rounds += 1
            if self.tool_rounds == 1:
                yield ToolCall(name="generate_questions", args={})
                return
            yield TextDelta(delta="已生成。")
            return
        yield TextDelta(delta="讲解")


def _question_with_figures() -> dict:
    return {
        "subject": "数学",
        "grade": 4,
        "knowledge_point": "图形的运动（轴对称）",
        "qtype": "choice",
        "stem": "下面哪些图形是轴对称图形？",
        "options": [
            {"text": "A. 正方形", "figure_key": "square"},
            {"text": "B. 平行四边形", "figure_key": "para"},
        ],
        "answer": "A. 正方形",
        "explanation": "正方形有四条对称轴。",
        "difficulty": "medium",
    }


def _run_figures(db, *, teacher_id, message: str = "出2道四年级数学选择题"):
    provider = _FigureProvider()
    agent = TasksSubAgent(provider=provider, retriever=None)
    ctx = SubAgentContext(
        role="teacher",
        message=message,
        extra={
            # 知识点必须与题卡一致：scene_spec 按规格里的知识点找模板。
            "specs": [
                _spec(
                    "数学", grade=4, count=1,
                    knowledge_point="图形的运动（轴对称）",
                )
            ],
            "teacher_id": teacher_id,
        },
    )

    async def _go():
        return [ev async for ev in agent.run(message, ctx, session=db)]

    return asyncio.run(_go())


def test_stream_question_card_stamps_option_figures(db):
    """题卡选项的 ``figure_key`` 在**流式帧上**就盖成内联几何（ADR-0102）。

    为什么必须在这一层做：题卡先经 SSE 到前端（用户当场看到图），再由前端原样回传
    落库。只在前端着色 → 后端不盖章题卡是纯文字；只在落库时盖章 → 聊天里永远没图。
    模型只给身份键、绝不产出顶点（ADR-0089）；几何权威是图库。
    """
    teacher_id = uuid.uuid4()
    events = _run_figures(db, teacher_id=teacher_id)
    cards = [
        e.data["result"]
        for e in events
        if e.eventType == EVENT_DATA and e.data and e.data.get("type") == "question"
    ]
    assert cards, "应产出题卡"
    options = cards[0]["options"]
    assert [o["text"] for o in options] == ["A. 正方形", "B. 平行四边形"]
    for option in options:
        assert "figure_key" not in option, "下发前必须已盖章，前端不该再看到身份键"
        figure = option["figure"]
        assert figure is not None, "每个选项都要有几何（全-or-无）"
        assert figure["key"] in {"square", "para"}
        assert len(figure["points"]) >= 3
        assert figure["edges"], "几何必须带连接关系"


def test_stream_question_card_attaches_scene_spec(db):
    """题卡带本题交互讲解快照（``scene_spec``），前端当场可演示（ADR-0102）。

    与落库路径共用 ``build_scene_spec_for_question``；知识点配了模板才有——没配时
    不写该键（写 None 会让前端误以为「有 spec 但解析失败」）。
    """
    teacher_id = uuid.uuid4()
    from app.db.models import KnowledgePoint

    db.add(
        KnowledgePoint(
            id=uuid.uuid4(), teacher_id=teacher_id, subject="数学", grade=4,
            semester="", name="图形的运动（轴对称）",
            scenes=[{
                "kind": "reflection",
                "figure": {
                    "key": "house", "label": "房子",
                    "points": [[0.3, 0.7], [0.7, 0.7], [0.7, 0.45], [0.5, 0.25], [0.3, 0.45]],
                    "edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]],
                },
                "curated": False,
            }],
        )
    )
    db.commit()

    events = _run_figures(db, teacher_id=teacher_id)
    card = next(
        e.data["result"]
        for e in events
        if e.eventType == EVENT_DATA and e.data and e.data.get("type") == "question"
    )
    spec = card.get("scene_spec")
    assert isinstance(spec, dict), "知识点配了模板 → 题卡必须带 scene_spec"
    assert spec["kind"] == "reflection"
    assert spec["figure"]["key"] == "house"


def test_stream_question_card_without_template_omits_scene_spec(db):
    """知识点没配模板 → **不写** scene_spec 键（而非写 None）。"""
    events = _run_figures(db, teacher_id=uuid.uuid4())
    card = next(
        e.data["result"]
        for e in events
        if e.eventType == EVENT_DATA and e.data and e.data.get("type") == "question"
    )
    assert "scene_spec" not in card


def test_invalid_figure_key_degrades_to_text_not_crash(db):
    """身份键非法（模型幻觉）→ 整题退化纯文字，不抛、不半套出图。"""
    teacher_id = uuid.uuid4()

    class _HallucinatedProvider(_FigureProvider):
        async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
            if schema is not None:
                data = _question_with_figures()
                game = dict(data["options"][0])
                game["figure_key"] = "not_in_library"
                data["options"] = [game, {**data["options"][1], "figure_key": "para"}]
                yield TextDelta(delta="出题。")
                yield StructuredDone(data=data)
                return
            if tools:
                self.tool_rounds += 1
                if self.tool_rounds == 1:
                    yield ToolCall(name="generate_questions", args={})
                    return
                yield TextDelta(delta="已生成。")
                return
            yield TextDelta(delta="讲解")

    agent = TasksSubAgent(provider=_HallucinatedProvider(), retriever=None)
    ctx = SubAgentContext(
        role="teacher",
        message="出2道四年级数学选择题",
        extra={"specs": [_spec("数学", grade=4, count=1)], "teacher_id": teacher_id},
    )

    async def _go():
        return [
            ev
            async for ev in agent.run("出2道四年级数学选择题", ctx, session=db)
        ]

    events = asyncio.run(_go())
    card = next(
        e.data["result"]
        for e in events
        if e.eventType == EVENT_DATA and e.data and e.data.get("type") == "question"
    )
    options = card["options"]
    assert [o["text"] for o in options] == ["A. 正方形", "B. 平行四边形"]
    assert all(o["figure"] is None for o in options), (
        "全-or-无：任一键不合法 → 整题纯文字（半套图会误导成「这个选项不是图形」）"
    )
