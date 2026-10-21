"""已确认规格的跨轮回灌（ADR-0099 → ADR-0104 下线）。

背景（ADR-0099 时代）：``Conversation.slots`` 早就持久化了已确认规格，但注入条件
绑定在「本轮抽到槽或刚补齐」上。续话（「再出几道」）不含槽关键词 → 不注入 →
出题子代理只能从会被 compaction 压缩的历史里重建规格，表现为「上一轮说了三年级
这一轮又问一遍」。当时的修法是把闸门放宽到「消息含本业务意图词」。

ADR-0104：规则路由移除、出题子意图分组（intent_schemas / trigger）下线后，
**聊天链路不再回灌 specs**——出题走纯 LLM 自由文本生成，规格由模型从对话历史
自行重建（history 每轮全量进上下文，见 runtime.decide 的 ``history`` 透传）。
本文件因此从「锁回灌」翻转为「锁不回流」：

1. 续话（无新槽）**不**把旧规格注入 ``ctx.extra["specs"]``；
2. 续话**不**重发「已确认规格」汇总帧；
3. 长会话把首轮压掉后**不**回灌（不依赖历史重建由模型自己负责）；
4. 换科目 / 年级的轮次同样静默（无汇总帧、无 specs）。

按规格的结构化出题仍由 ``POST /tasks/generate``（``ctx.extra["specs"]``）承载，
其规格合并语义（``merge_spec_layers`` / ``specs_from_context``）由本文件尾部用例
继续守护——那条路径不随聊天链路变化。
"""
from __future__ import annotations

import asyncio
import json
import uuid
from types import SimpleNamespace

from agent_core.protocol import EVENT_DATA, data_event, done
from agent_core.runtime import RouteDecision
from agent_core.subagent import SubAgentContext
from app.ai.subagents.tasks.generation.specs import (
    merge_spec_layers,
    specs_from_context,
)
from app.features.assistant.schemas import AssistantChatReq
from app.features.assistant.service import chat


def _caller(role: str, *, user_id: uuid.UUID, teacher_id: uuid.UUID):
    return SimpleNamespace(
        role=role,
        user=SimpleNamespace(id=user_id, teacher_id=teacher_id, class_id=None),
    )


class _StubRuntime:
    """桩 runtime：只记录本轮看到的 ``ctx.extra``，产出一张题卡。

    ADR-0104：无 trigger 子意图词，桩只按 business 决策（出题问句 → tasks）。
    """

    def __init__(self) -> None:
        self.last_ctx_extra = None

    async def decide(self, signal, *, role: str, deps, history=None) -> RouteDecision:
        return RouteDecision(business="tasks", name="任务学情与出题助手")

    async def run(
        self, message, *, role, ctx, deps, business=None, session=None, allow_reroute=False
    ):
        self.last_ctx_extra = ctx.extra
        yield data_event(
            {"subject": "数学", "stem": "1+1=?", "options": ["2"], "answer": "2"},
            extra={"type": "question"},
        )
        yield done(ctx.extra.get("session_id"))


def _req(message: str, *, session_id=None) -> AssistantChatReq:
    return AssistantChatReq(message=message, session_id=session_id)


def _parse(frames: list[str]) -> list[dict]:
    return [
        json.loads(f[6:].strip()) for f in frames if f.startswith("data: ")
    ]


def _send(db, rt, message: str, *, pid: uuid.UUID, session_id: str | None = None):
    async def _go():
        gen = await chat(
            caller=_caller("teacher", user_id=pid, teacher_id=pid),
            req=_req(message, session_id=session_id),
            session=db,
            runtime=rt,
        )
        return [frame async for frame in gen]

    return _parse(asyncio.run(_go()))


def _collect(db, rt, *, pid: uuid.UUID) -> str:
    """跑完一轮「出数学三年级选择题」，返回会话 id。"""
    _send(db, rt, "帮我出2道三年级数学选择题", pid=pid)
    return str(rt.last_ctx_extra["session_id"])


def test_followup_turn_does_not_reinject_specs(db):
    """续话（「再出几道」）不注入 specs：聊天链路纯 LLM 生成（ADR-0104）。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect(db, rt, pid=pid)

    _send(db, rt, "再出几道", pid=pid, session_id=sid)

    assert not (rt.last_ctx_extra or {}).get("specs"), "纯 LLM 生成不得回灌旧规格"


def test_followup_turn_does_not_resend_summary_frame(db):
    """汇总帧已随出题引导下线：续话轮不弹，也不该在任何轮次弹。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect(db, rt, pid=pid)

    events = _send(db, rt, "再出几道", pid=pid, session_id=sid)

    assert not [
        e for e in events if (e.get("extra") or {}).get("summary")
    ], "不应出现「已确认规格」帧"
    assert any(e["eventType"] == EVENT_DATA for e in events), "仍应正常出题"


def test_unrelated_message_does_not_reinject(db):
    """「谢谢」这类无关话同样不注入——纯 LLM 生成下 specs 恒不回流。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect(db, rt, pid=pid)

    rt2 = _StubRuntime()
    _send(db, rt2, "谢谢", pid=pid, session_id=sid)

    assert not (rt2.last_ctx_extra or {}).get("specs"), "无关消息不得复用旧规格出题"


def test_spec_change_turn_is_silent(db):
    """换科目/年级的轮次：无 specs 注入、无汇总帧（引导链路已下线）。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect(db, rt, pid=pid)

    events = _send(db, rt, "换成一年级语文选择题，再出几道", pid=pid, session_id=sid)

    assert not (rt.last_ctx_extra or {}).get("specs")
    assert not [e for e in events if (e.get("extra") or {}).get("summary")]


def test_long_conversation_does_not_reinject(db):
    """长会话把首轮压掉后也不回灌——规格重建由模型从 history 自行负责。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect(db, rt, pid=pid)
    # 灌入大量闲聊轮次，把首轮的规格描述挤出 compaction 窗口
    for i in range(25):
        _send(db, rt, f"第{i}个补充说明", pid=pid, session_id=sid)

    _send(db, rt, "再出几道", pid=pid, session_id=sid)

    assert not (rt.last_ctx_extra or {}).get("specs")


def test_new_conversation_starts_with_empty_slots(db):
    """规格的生命周期边界 = 会话：新会话不继承旧会话的槽位。"""
    from sqlmodel import select

    from app.db.models import Conversation

    pid = uuid.uuid4()
    rt = _StubRuntime()
    _collect(db, rt, pid=pid)
    _send(db, rt, "再出一道题", pid=pid)  # 不传 session_id → 新会话

    convs = list(
        db.exec(select(Conversation).where(Conversation.teacher_id == pid)).all()
    )
    assert len(convs) == 2, "不传 session_id 应新建会话"
    newest = max(convs, key=lambda c: c.created_at)
    # 新会话本轮自己也抽到了槽，但应是它自己的，而非旧会话的（按 business 单键存）。
    slots = (newest.slots or {}).get("tasks") or {}
    assert slots.get("grade") != 3, "新会话不得继承旧会话已确认的年级"


# ── 规格合并语义（specs.merge_spec_layers，结构化端点路径仍用） ──────────────────


def test_merge_layers_overrides_without_double_counting():
    """基底 count=3 + 模型 args count=2 → 取 2，而不是 5。"""
    base = [{"subject": "数学", "grade": 3, "qtype": "choice", "count": 3}]
    overrides = [{"subject": "数学", "grade": 0, "qtype": "", "count": 2}]
    merged = merge_spec_layers(base, overrides)
    assert len(merged) == 1
    assert merged[0]["count"] == 2
    # 缺席编码（grade=0 / qtype=""）不覆盖基底
    assert merged[0]["grade"] == 3
    assert merged[0]["qtype"] == "choice"


def test_merge_layers_keeps_base_when_overrides_absent():
    base = [{"subject": "数学", "grade": 3}]
    assert merge_spec_layers(base, []) == base
    assert merge_spec_layers([], [{"subject": "语文"}]) == [{"subject": "语文"}]


def test_end_to_end_count_not_doubled():
    """基底规格 + args 同 count → 展开后的题数等于某一方，不是两者之和。"""
    ctx = SubAgentContext(role="teacher", message="再出2道")
    specs = merge_spec_layers(
        [{"subject": "数学", "grade": 3, "qtype": "choice", "count": 2}],
        [{"subject": "", "grade": 0, "qtype": "", "count": 2}],
    )
    assert len(specs_from_context(specs, ctx=ctx)) == 2
