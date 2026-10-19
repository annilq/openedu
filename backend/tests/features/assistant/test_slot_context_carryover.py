"""已确认规格的跨轮回灌（ADR-0099）。

背景：``Conversation.slots`` 早就持久化了已确认规格，但注入条件绑定在「本轮抽到槽
或刚补齐」上。续话（「再出几道」）不含槽关键词 → 不注入 → 出题子代理只能从会被
compaction 压缩的历史里重建规格，表现为「上一轮说了三年级这一轮又问一遍」。

本文件锁三条行为：
1. 续话（无新槽）仍把已确认规格注入 ``ctx.extra["specs"]``；
2. 续话**不再**重发「已确认规格」汇总帧（避免每轮弹一遍）；
3. 规格以「基底 + 覆盖」合并，不与模型 args 各自展开而让 count 相加。
"""
from __future__ import annotations

import asyncio
import json
import uuid
from types import SimpleNamespace

from agent_core.protocol import EVENT_DATA, data_event, done
from agent_core.runtime import RouteDecision
from agent_core.subagent import SubAgentContext
from app.ai.subagents.question.specs import merge_spec_layers, specs_from_context
from app.features.assistant.schemas import AssistantChatReq
from app.features.assistant.service import chat


def _caller(role: str, *, user_id: uuid.UUID, teacher_id: uuid.UUID):
    return SimpleNamespace(
        role=role,
        user=SimpleNamespace(id=user_id, teacher_id=teacher_id, class_id=None),
    )


class _StubRuntime:
    """桩 runtime：只记录本轮看到的 ``ctx.extra``，产出一张题卡。"""

    def __init__(self) -> None:
        self.last_ctx_extra = None

    async def decide(self, signal, *, role: str, deps) -> RouteDecision:
        return RouteDecision(business="question", name="题库与出题助手")

    async def run(self, message, *, role, ctx, deps, business=None, session=None):
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


def _collect_specs(db, rt, *, pid: uuid.UUID) -> str:
    """跑完一轮「出数学三年级选择题」，返回会话 id。"""
    _send(db, rt, "出2道三年级数学选择题", pid=pid)
    return str(rt.last_ctx_extra["session_id"])


def test_followup_turn_reinjects_confirmed_specs(db):
    """续话不含任何槽关键词，仍须把已确认规格交给生成器。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect_specs(db, rt, pid=pid)

    _send(db, rt, "再出几道", pid=pid, session_id=sid)

    specs = (rt.last_ctx_extra or {}).get("specs")
    assert isinstance(specs, list) and specs, "续话轮必须复用已确认规格"
    assert specs[0]["subject"] == "数学"
    assert specs[0]["grade"] == 3
    assert specs[0]["qtype"] == "choice"


def test_followup_turn_does_not_resend_summary_frame(db):
    """汇总帧只在本轮带来新/变更规格时下发，续话轮不重复弹。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect_specs(db, rt, pid=pid)

    events = _send(db, rt, "再出几道", pid=pid, session_id=sid)

    assert not [
        e for e in events if (e.get("extra") or {}).get("summary")
    ], "续话轮不应重发「已确认规格」帧"
    assert any(e["eventType"] == EVENT_DATA for e in events), "仍应正常出题"


def test_unrelated_message_does_not_reinject(db):
    """「谢谢」既无意图词也未抽到槽 → 不注入，不拿旧规格再出一轮题。

    注：真实路由会把「谢谢」判到 tutor（question 无匹配词，三级兜底落 priority
    最低的 tutor）。这里桩 runtime 恒返回 question，故意把消息送到分支前，
    以锁定**服务端自己的闸门**不依赖路由兜底。
    """
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect_specs(db, rt, pid=pid)

    rt2 = _StubRuntime()
    _send(db, rt2, "谢谢", pid=pid, session_id=sid)

    assert not (rt2.last_ctx_extra or {}).get("specs"), "无关消息不得复用旧规格出题"


def test_new_turn_overrides_slot_and_does_resend_summary(db):
    """换科目/年级时：规格被覆盖，并照常下发汇总帧。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect_specs(db, rt, pid=pid)

    events = _send(db, rt, "换成一年级语文选择题", pid=pid, session_id=sid)

    specs = (rt.last_ctx_extra or {}).get("specs")
    assert specs[0]["subject"] == "语文"
    assert specs[0]["grade"] == 1
    assert [e for e in events if (e.get("extra") or {}).get("summary")], (
        "带来变更规格的轮次仍应下发汇总帧"
    )


def test_injected_specs_survive_compaction(db):
    """长会话把首轮压掉后，已确认规格仍从 slots 回灌（不依赖历史）。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
    sid = _collect_specs(db, rt, pid=pid)
    # 灌入大量闲聊轮次，把首轮的规格描述挤出 compaction 窗口
    for i in range(25):
        _send(db, rt, f"第{i}个补充说明", pid=pid, session_id=sid)

    _send(db, rt, "再出几道", pid=pid, session_id=sid)

    specs = (rt.last_ctx_extra or {}).get("specs")
    assert specs and specs[0]["subject"] == "数学" and specs[0]["grade"] == 3


def test_new_conversation_starts_with_empty_slots(db):
    """规格的生命周期边界 = 会话：新会话不继承旧会话的槽位。"""
    from sqlmodel import select

    from app.db.models import Conversation

    pid = uuid.uuid4()
    rt = _StubRuntime()
    _collect_specs(db, rt, pid=pid)
    _send(db, rt, "再出一道题", pid=pid)  # 不传 session_id → 新会话

    convs = list(
        db.exec(select(Conversation).where(Conversation.teacher_id == pid)).all()
    )
    assert len(convs) == 2, "不传 session_id 应新建会话"
    newest = max(convs, key=lambda c: c.created_at)
    # 新会话本轮自己也抽到了「题」但无科目 → 槽位应是它自己的，而非旧会话的。
    slots = (newest.slots or {}).get("question") or {}
    assert slots.get("grade") != 3, "新会话不得继承旧会话已确认的年级"


# ── 规格合并语义（specs.merge_spec_layers） ──────────────────────────────────


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
