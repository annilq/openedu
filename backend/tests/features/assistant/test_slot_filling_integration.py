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
    # 已持久化已知槽位（subject=数学），grade 尚未收集
    conv = _latest_conv(db, teacher_id=pid)
    assert conv is not None
    assert conv.slots.get("subject") == "数学"
    assert "grade" not in (conv.slots or {})


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
    assert conv.slots["subject"] == "数学"
    assert conv.slots["grade"] == 3
    assert conv.slots["qtype"] == "choice"


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
