"""缺槽预检端到端集成（ADR-0095 / ADR-0098，tasks 业务 generate 意图）。

用桩 AgentRuntime 驱动 ``chat``，断言：缺 subject/grade 时响应含 ``extra.clarify`` 且
无非澄清 DATA 帧；下一轮只补 grade+qtype 则合并后继续生成；必填齐备（如带课件上下文）
仍正常出 DATA 卡（结构化路径行为不变回归）。

ADR-0098：question 域并入 tasks，预检按 ``(business, trigger)`` 分子意图——桩按
``trigger`` 配置：给 generate 组触发词（默认）时走出题槽位预检，槽位落
``tasks:generate`` 键；给非 generate 词 / ``None`` 时走默认 schema（恒放行）。
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

from app.db.models import Conversation, Message
from app.features.assistant.schemas import AssistantChatReq, CoursewareContext
from app.features.assistant.service import chat


def _caller(role: str, *, user_id: uuid.UUID, teacher_id: uuid.UUID):
    return SimpleNamespace(role=role, user=SimpleNamespace(id=user_id, teacher_id=teacher_id, class_id=None))


class _StubRuntime:
    """桩 runtime：产出一张题卡（DATA 帧）。

    ADR-0098：question 并入 tasks 后，预检按 ``(business, trigger)`` 选 schema。
    默认配置模拟真实路由对出题问句的决策（business=tasks、命中 generate 组触发词）；
    ``trigger`` 显式配非 generate 词或 ``None`` 时模拟学情 / 问答类决策。
    """

    def __init__(self, business: str = "tasks", trigger: str | None = "出题") -> None:
        self.business = business
        self.trigger = trigger
        self.last_ctx_extra = None

    async def decide(self, signal, *, role: str, deps) -> RouteDecision:
        return RouteDecision(
            business=self.business, name="桩业务", trigger=self.trigger
        )

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
    rt = _StubRuntime()
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
    # 已持久化已知槽位（subject=数学），grade 尚未收集。槽位按 business:intent 分组存放。
    conv = _latest_conv(db, teacher_id=pid)
    assert conv is not None
    assert conv.slots["tasks:generate"]["subject"] == "数学"
    assert "grade" not in (conv.slots["tasks:generate"] or {})


def test_clarify_round_yields_done_and_followup_continues_same_conversation(db):
    """澄清轮必须下发 DONE（带 session_id），否则续接会新建会话、把首轮孤立。

    回归：缺槽预检在 ``rt.run`` 之前 return，而 DONE 帧由 ``rt.run`` 的 finally 产出
    （agent_core/runtime.py:191）→ 澄清轮原本收不到 DONE。前端 ``_currentSessionId``
    据此回写，缺失则下一句以 sessionId=null 新建会话，表现即「运行详情 / 会话详情都缺第一轮」。
    """
    pid = uuid.uuid4()
    rt = _StubRuntime()

    # 第一轮：缺 grade/qtype → 澄清（不调 rt.run）
    frames1 = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("出几道数学题"),
                session=db,
                runtime=rt,
            )
        )
    )
    events1 = _parse(frames1)
    done_frames1 = [e for e in events1 if e["eventType"] == "DONE"]
    assert done_frames1, "澄清轮必须下发 DONE 帧（回归点）"
    sid = done_frames1[0].get("session_id")
    assert sid, "DONE 帧必须回写 session_id"

    # 澄清消息只落一条（修复前 finally 的 final_text 会重复落一条助手消息）
    cid = uuid.UUID(sid)
    clarify_msgs = db.exec(
        select(Message).where(
            Message.conversation_id == cid,
            Message.role == "assistant",
            Message.step == "output",
        )
    ).all()
    assert len(clarify_msgs) == 1, "澄清消息不应重复落库"

    # 第二轮：补齐 grade/qtype → 走到 rt.run 生成题卡；带 sid 续接同一会话
    frames2 = asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("三年级选择题", session_id=sid),
                session=db,
                runtime=rt,
            )
        )
    )
    events2 = _parse(frames2)
    assert any(e["eventType"] == EVENT_DATA for e in events2), "补齐后应生成题卡"

    # 续接：会话数仍为 1，首轮 user 消息保留在第一条
    convs = db.exec(
        select(Conversation).where(Conversation.teacher_id == pid)
    ).all()
    assert len(convs) == 1, "续接不应新建会话"
    assert convs[0].id == cid
    user_msgs = db.exec(
        select(Message)
        .where(Message.conversation_id == cid, Message.role == "user")
        .order_by(Message.turn)
    ).all()
    assert user_msgs[0].turn == 0
    assert "出几道数学题" in (user_msgs[0].content or ""), "首轮 user 消息必须保留"


def test_second_turn_merges_and_generates(db):
    """第一轮缺 grade/qtype；第二轮补「三年级出选择题」→ 合并后继续生成。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
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
    assert conv.slots["tasks:generate"]["subject"] == "数学"
    assert conv.slots["tasks:generate"]["grade"] == 3
    assert conv.slots["tasks:generate"]["qtype"] == "choice"


def test_complete_specs_still_generate(db):
    """必填齐备（带课件 subject/grade）+ 文本 qtype → 汇总帧后正常出题（回归不误阻塞）。"""
    pid = uuid.uuid4()
    rt = _StubRuntime()
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
    "business,trigger,text",
    [
        # tasks 默认意图（学情 / 名单，ADR-0098）：非 generate 触发词 → 全 optional
        ("tasks", "错题", "看看我的错题"),
        ("tasks", "我班", "我班有哪些学生"),
        ("tutor", None, "为什么天空是蓝的"),
    ],
)
def test_non_question_businesses_never_clarify(db, business, trigger, text):
    """预检已扩展到全部业务，但默认意图 / tutor 全 optional → 永不追问。

    ADR-0098：名单问句随 students 域吸收进 tasks（默认意图），仍不触发任何澄清。
    tutor 的 question_text 亦为**非必填**（消息本身就是问题），否则自由问答会被
    恒追问「你想问什么？」而阻塞（ADR-0095 §2.4）。
    """
    pid = uuid.uuid4()
    rt = _StubRuntime(business=business, trigger=trigger)
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
    """汇总确认帧只对 generate 意图发；tutor 等问答/只读意图不发（避免噪声）。"""
    pid = uuid.uuid4()
    rt = _StubRuntime(business="tutor", trigger=None)
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
    # 也不该给非 generate 意图注入 specs（它们不按规格生成）
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
    rt = _StubRuntime()
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
    assert conv.slots["tasks:generate"]["grade"] == 3, "grade 必须跨轮记住"

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


def test_other_business_does_not_clobber_generate_slots(db):
    """tutor 一轮之后，generate 意图已收集的槽位仍在（槽位按 business:intent 分组存）。

    回归：flat 存 + fill_slots 只搬当前 schema 内的键 → tutor 轮写回的 merged 不含
    出题的 grade/qtype，半成形意图被静默清空。
    """
    pid = uuid.uuid4()
    rt = _StubRuntime()
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
    assert conv.slots["tasks:generate"]["subject"] == "数学"

    tutor_rt = _StubRuntime(business="tutor", trigger=None)
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
    assert conv.slots["tasks:generate"]["subject"] == "数学", "tutor 轮不得冲掉出题槽位"


def test_unrelated_followup_does_not_regenerate(db):
    """槽位齐备后再说与出题无关的话（如「谢谢」）→ 不按旧规格再出一轮题。

    回归：齐备即注入 specs 会让此后**每一条**消息都重出题，用户根本没法正常聊天。
    """
    pid = uuid.uuid4()
    rt = _StubRuntime()
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

    rt2 = _StubRuntime()
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
    rt = _StubRuntime()
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


def test_replay_bubbles_carry_clarify_and_summary(db):
    """回放气泡带 clarify / summary 两个结构化 extra，且不透传 payload 其余键。

    两轮对话（第一轮缺 grade/qtype → 澄清；第二轮补齐 → 汇总 + 生成）之后调
    ``read_conversation_bubbles``：澄清行与汇总行的气泡必须各带一个结构化载荷，
    形状与实时流的 ``extra`` 一致（同一份解析）。同时断言**白名单**语义——气泡只有
    role/text/cards/clarify/summary 五个键，审计面字段不被拖进用户面。
    """
    from app.features.assistant.repository import read_conversation_bubbles

    pid = uuid.uuid4()
    rt = _StubRuntime()
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
    asyncio.run(
        _drain(
            chat(
                caller=_caller("teacher", user_id=pid, teacher_id=pid),
                req=_req("三年级出选择题", session_id=sid),
                session=db,
                runtime=rt,
            )
        )
    )

    bubbles = read_conversation_bubbles(db, conv.id)
    # 第二轮是「汇总帧 + 题卡」两个 assistant 行（final_text or cards 才落库），
    # 所以一共 5 条而不是 4 条。
    assert [b["role"] for b in bubbles] == [
        "user",
        "assistant",
        "user",
        "assistant",
        "assistant",
    ]

    clarify_bubble = bubbles[1]
    assert clarify_bubble["clarify"] is not None
    slots = clarify_bubble["clarify"]["missing_slots"]
    assert [s["name"] for s in slots] == ["grade", "qtype"]
    # 白名单：气泡不带 payload 里的审计面字段
    assert set(clarify_bubble) == {"role", "text", "cards", "clarify", "summary"}
    assert clarify_bubble["summary"] is None

    summary_bubble = bubbles[3]
    assert summary_bubble["summary"] is not None
    # 汇总带**全部**槽（含可选）：required 三项在前，可选槽随后
    names = [
        s["slot"]["name"] if "slot" in s else s["name"]
        for s in summary_bubble["summary"]["slots"]
    ]
    assert names[:3] == ["subject", "grade", "qtype"]
    assert set(names[:3]) <= set(names)
    assert summary_bubble["clarify"] is None

    # 汇总之后的生成行：题卡整帧照常投影（卡片链路不受结构化 extra 影响）
    gen_bubble = bubbles[4]
    assert gen_bubble["cards"], "汇总轮生成的题卡应随气泡回来"


def test_clarify_message_text_is_one_shot_guidance(db):
    """澄清帧正文是一句「还差什么 + 怎么一次说全」，不是逐槽反问（ADR-0100）。

    旧正文是各缺槽 ``prompt`` 空格拼接（「请问要出哪个科目？ 几年级？（1-9） 要什么
    题型？」），气泡里念成一串反问，且与前端铺出的选项 chip 重复。ADR-0100 把引导
    收回一句话：用户回一句「三年级数学、选择题」即补齐，不必点三次。
    """
    pid = uuid.uuid4()
    rt = _StubRuntime()
    events = _parse(
        asyncio.run(
            _drain(
                chat(
                    caller=_caller("teacher", user_id=pid, teacher_id=pid),
                    req=_req("出几道题"),
                    session=db,
                    runtime=rt,
                )
            )
        )
    )
    clarify = next(e for e in events if e.get("extra", {}).get("clarify"))
    text = clarify["text"]
    # 三个缺槽的中文标签都在一句话里
    for label in ("科目", "年级", "题型"):
        assert label in text, f"正文必须点名缺哪个槽（{label}）"
    assert "一次" in text, "必须告诉用户可以一次说完"
    assert "例如" in text, "必须给可照抄的示例句"
    # 逐槽的反问句不再出现在正文里
    assert "？" not in text, "正文不该是一串反问"
    # 协议侧 missing_slots 照旧下发
    names = {m["name"] for m in clarify["extra"]["clarify"]["missing_slots"]}
    assert names == {"subject", "grade", "qtype"}
