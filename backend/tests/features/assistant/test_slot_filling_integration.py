"""缺槽预检端到端集成（ADR-0095，question 业务）。

用桩 AgentRuntime 驱动 ``chat``，断言：缺 subject/grade 时响应含 ``extra.clarify`` 且
无非澄清 DATA 帧；下一轮只补 grade+qtype 则合并后继续生成；必填齐备（如带课件上下文）
仍正常出 DATA 卡（结构化路径行为不变回归）。
"""
from __future__ import annotations

import asyncio
import json
import uuid
from types import SimpleNamespace

import pytest

from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    data_event,
    done,
)
from agent_core.runtime import RouteDecision
from sqlmodel import select

from app.db.models import Conversation
from app.features.assistant.schemas import AssistantChatReq, CoursewareContext
from app.features.assistant.service import chat


def _caller(role: str, *, user_id: uuid.UUID, teacher_id: uuid.UUID):
    return SimpleNamespace(role=role, user=SimpleNamespace(id=user_id, teacher_id=teacher_id, class_id=None))


class _QuestionStubRuntime:
    """桩 runtime：产出一张题卡（DATA 帧）；business 可配（默认 question）。"""

    def __init__(self, business: str = "question") -> None:
        self.business = business
        self.last_ctx_extra = None

    async def decide(self, signal, *, role: str, deps) -> RouteDecision:
        return RouteDecision(business=self.business, name="桩业务")

    async def run(self, message, *, role, ctx, deps, business=None, session=None):
        self.last_ctx_extra = ctx.extra
        yield data_event(
            {"subject": "数学", "stem": "1+1=?", "options": ["2"], "answer": "2"},
            extra={"type": "question"},
        )
        yield done(ctx.extra.get("session_id"))


def _req(message: str, *, session_id=None, courseware=None) -> AssistantChatReq:
    return AssistantChatReq(message=message, session_id=session_id, courseware=courseware)


async def _drain(chat_coro) -> list[str]:
    gen = await chat_coro
    return [frame async for frame in gen]


def _parse(frames: list[str]) -> list[dict]:
    out = []
    for f in frames:
        if f.startswith("data: "):
            out.append(json.loads(f[len("data: ") :].strip()))
    return out


def _latest_conv(db, *, teacher_id: uuid.UUID) -> Conversation:
    return db.exec(
        select(Conversation).where(Conversation.teacher_id == teacher_id)
    ).first()


def test_missing_slots_yields_clarify_and_no_data_card(db):
    """缺 grade/qtype → 响应含 extra.clarify，且整条流无非澄清 DATA 帧。"""
    pid = uuid.uuid4()
    rt = _QuestionStubRuntime()
    frames = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("出几道数学题"),
                session=db,
                runtime=rt,
            )
        )
    )
    events = _parse(frames)
    clarify_frames = [e for e in events if e.get("extra", {}).get("clarify")]
    assert clarify_frames, "应产出澄清帧"
    missing = clarify_frames[0]["extra"]["clarify"]["missing_slots"]
    missing_names = {m["name"] for m in missing}
    assert {"grade", "qtype"} <= missing_names
    # 无生成（无 DATA 帧）；澄清轮不调 rt.run
    assert not [e for e in events if e["eventType"] == EVENT_DATA]
    assert rt.last_ctx_extra is None
    # 已持久化已知槽位（subject=数学），grade 尚未收集。槽位按 business 分组存放。
    conv = _latest_conv(db, teacher_id=pid)
    assert conv is not None
    assert conv.slots["question"]["subject"] == "数学"
    assert "grade" not in (conv.slots["question"] or {})


def test_second_turn_merges_and_generates(db):
    """第一轮缺 grade/qtype；第二轮补「三年级出选择题」→ 合并后继续生成。"""
    pid = uuid.uuid4()
    rt = _QuestionStubRuntime()
    # 第一轮
    asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("出几道数学题"),
                session=db,
                runtime=rt,
            )
        )
    )
    conv = _latest_conv(db, teacher_id=pid)
    assert conv is not None
    sid = str(conv.id)
    # 第二轮：只补 grade + qtype
    frames2 = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("三年级出选择题", session_id=sid),
                session=db,
                runtime=rt,
            )
        )
    )
    events2 = _parse(frames2)
    # 本轮不再澄清（merged 已齐备），且产出了题卡 DATA 帧
    assert not [e for e in events2 if e.get("extra", {}).get("clarify")]
    assert any(e["eventType"] == EVENT_DATA for e in events2)
    # 预检必须把合并后的槽位交给出题子代理的结构化规格路径（ctx.extra["specs"]），
    # 否则生成步会重新回落自由文本兜底、丢失已收集的科目/年级/题型。
    specs = (rt.last_ctx_extra or {}).get("specs")
    assert isinstance(specs, list) and specs, "完整轮必须把合并槽位交给 specs"
    handed = specs[0]
    assert handed["subject"] == "数学"
    assert handed["grade"] == 3
    assert handed["qtype"] == "choice"
    # 合并后的槽位已落库：subject(沿用) + grade + qtype
    conv = db.get(Conversation, uuid.UUID(sid))
    assert conv.slots["question"]["subject"] == "数学"
    assert conv.slots["question"]["grade"] == 3
    assert conv.slots["question"]["qtype"] == "choice"


def test_complete_specs_still_generate(db):
    """必填齐备（带课件 subject/grade）+ 文本 qtype → 汇总帧后正常出题（回归不误阻塞）。"""
    pid = uuid.uuid4()
    rt = _QuestionStubRuntime()
    frames = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req(
                    "出一道选择题",
                    courseware=CoursewareContext(subject="数学", grade=4),
                ),
                session=db,
                runtime=rt,
            )
        )
    )
    events = _parse(frames)
    # 有汇总确认 ASSISTANT_MESSAGE
    assert any(
        e["eventType"] == EVENT_ASSISTANT_MESSAGE and "已确认规格" in e.get("text", "")
        for e in events
    )
    # 仍正常出题；且结构化路径收到 specs（科目/年级/题型齐全）
    assert any(e["eventType"] == EVENT_DATA for e in events)
    assert (rt.last_ctx_extra or {}).get("specs"), "完整轮必须注入 specs"


@pytest.mark.parametrize(
    "business,text",
    [
        ("query", "看看我的错题"),
        ("tutor", "为什么天空是蓝的"),
        ("guide", "帮我创建一个任务"),
    ],
)
def test_non_question_businesses_never_clarify(db, business, text):
    """预检已扩展到全部业务，但 query/guide/tutor 全 optional → 永不追问。

    tutor 的 question_text 亦为**非必填**（消息本身就是问题），否则自由问答会被
    恒追问「你想问什么？」而阻塞（ADR-0095 §2.4）。
    """
    pid = uuid.uuid4()
    rt = _QuestionStubRuntime(business=business)
    frames = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req(text),
                session=db,
                runtime=rt,
            )
        )
    )
    events = _parse(frames)
    assert not [e for e in events if e.get("extra", {}).get("clarify")], (
        f"{business} 不应产出澄清帧"
    )
    # 未被预检短路，正常进子代理生成
    assert rt.last_ctx_extra is not None, "应进入 rt.run"
    assert any(e["eventType"] == EVENT_DATA for e in events)


def test_tutor_does_not_emit_summary_frame(db):
    """汇总确认帧只对 question 发；tutor 等问答/只读业务不发（避免噪声）。"""
    pid = uuid.uuid4()
    rt = _QuestionStubRuntime(business="tutor")
    frames = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("为什么天空是蓝的"),
                session=db,
                runtime=rt,
            )
        )
    )
    events = _parse(frames)
    assert not any(
        e["eventType"] == EVENT_ASSISTANT_MESSAGE and "已确认规格" in e.get("text", "")
        for e in events
    ), "tutor 不应出现「已确认规格」汇总帧"
    # 也不该给非 question 业务注入 specs（它们不按规格生成）
    assert not (rt.last_ctx_extra or {}).get("specs")


def _clarify_missing(frames: list[str]) -> list[dict]:
    """取本轮澄清帧的 missing_slots（无则空列表）。"""
    for e in _parse(frames):
        clarify = e.get("extra", {}).get("clarify")
        if clarify:
            return clarify["missing_slots"]
    return []


def test_partial_fill_asks_only_remaining_required(db):
    """只补一个必填槽 → 只追问剩下的：grade 记住了，第二轮只问 qtype。

    边界澄清：qtype 同为必填（grill 决策 #4「出题加 qtype」），故 ticket 01 原话
    「只回三年级即可续接」不是「只回三年级就生成」——按 SPEC「半成形意图跨轮保存、
    下一轮只需补说缺失项」，它指已填槽不丢、只问仍缺的。本测试锁定该语义。
    """
    pid = uuid.uuid4()
    rt = _QuestionStubRuntime()
    _turn1 = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("出几道数学题"),
                session=db,
                runtime=rt,
            )
        )
    )
    assert {m["name"] for m in _clarify_missing(_turn1)} == {"grade", "qtype"}
    conv = _latest_conv(db, teacher_id=pid)
    sid = str(conv.id)

    # 第二轮只补年级
    _turn2 = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("三年级", session_id=sid),
                session=db,
                runtime=rt,
            )
        )
    )
    assert {m["name"] for m in _clarify_missing(_turn2)} == {"qtype"}, "只该问 qtype"
    assert not [e for e in _parse(_turn2) if e["eventType"] == EVENT_DATA]
    conv = db.get(Conversation, uuid.UUID(sid))
    assert conv.slots["question"]["grade"] == 3, "grade 必须跨轮记住"

    # 第三轮补题型 → 齐备，进入生成
    _turn3 = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("选择题", session_id=sid),
                session=db,
                runtime=rt,
            )
        )
    )
    assert not _clarify_missing(_turn3)
    assert (rt.last_ctx_extra or {}).get("specs")


def test_other_business_does_not_clobber_question_slots(db):
    """tutor 一轮之后，question 已收集的槽位仍在（槽位按 business 分组存）。

    回归：flat 存 + fill_slots 只搬当前 schema 内的键 → tutor 轮写回的 merged 不含
    question 的 grade/qtype，半成形意图被静默清空。
    """
    pid = uuid.uuid4()
    rt = _QuestionStubRuntime()
    asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("出几道数学题"),
                session=db,
                runtime=rt,
            )
        )
    )
    conv = _latest_conv(db, teacher_id=pid)
    sid = str(conv.id)
    assert conv.slots["question"]["subject"] == "数学"

    tutor_rt = _QuestionStubRuntime(business="tutor")
    asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("为什么天空是蓝的", session_id=sid),
                session=db,
                runtime=tutor_rt,
            )
        )
    )
    conv = db.get(Conversation, uuid.UUID(sid))
    assert conv.slots["question"]["subject"] == "数学", "tutor 轮不得冲掉 question 槽位"


def test_unrelated_followup_does_not_regenerate(db):
    """槽位齐备后再说与出题无关的话（如「谢谢」）→ 不按旧规格再出一轮题。

    回归：齐备即注入 specs 会让此后**每一条**消息都重出题，用户根本没法正常聊天。
    """
    pid = uuid.uuid4()
    rt = _QuestionStubRuntime()
    frames = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("出2道三年级数学选择题"),
                session=db,
                runtime=rt,
            )
        )
    )
    assert (rt.last_ctx_extra or {}).get("specs"), "首轮必须生成"
    conv = _latest_conv(db, teacher_id=pid)
    sid = str(conv.id)

    rt2 = _QuestionStubRuntime()
    frames2 = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("谢谢", session_id=sid),
                session=db,
                runtime=rt2,
            )
        )
    )
    events2 = _parse(frames2)
    assert not (rt2.last_ctx_extra or {}).get("specs"), "无新槽位不得再出题"
    assert not [e for e in events2 if e.get("extra", {}).get("summary")]


def test_clarify_message_payload_matches_frame_contract(db):
    """澄清消息落库 payload 与 extra.clarify 同形（map），不是裸 list。"""
    from sqlmodel import select

    from app.db.models import Message

    pid = uuid.uuid4()
    rt = _QuestionStubRuntime()
    asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("出几道数学题"),
                session=db,
                runtime=rt,
            )
        )
    )
    conv = _latest_conv(db, teacher_id=pid)
    rows = db.exec(
        select(Message).where(
            Message.conversation_id == conv.id, Message.role == "assistant"
        )
    ).all()
    stored = [r.payload for r in rows if isinstance(r.payload, dict) and "clarify" in r.payload]
    assert stored, "澄清帧应作为普通助手消息落库"
    assert isinstance(stored[0]["clarify"], dict)
    assert "missing_slots" in stored[0]["clarify"]
