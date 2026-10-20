"""缺槽预检端到端集成（ADR-0095 / ADR-0104：纯 LLM 生成后的预检行为）。

用桩 AgentRuntime 驱动 ``chat``，分两面断言：

**真实配置（ADR-0104 后）**：规则路由与出题子意图分组（intent_schemas / trigger）
一并移除，manifest 的 ``input_schema`` 全部 optional → 聊天链路**恒放行**：
不出澄清帧、不注入 ``ctx.extra["specs"]``、不发「已确认规格」汇总帧，直接进
``rt.run`` 生成；槽位按 business 单键持久化（``conversation.slots["tasks"]``），
跨轮合并照旧。出题引导（必填槽澄清 + 规格回显）随规则下线，按规格的结构化出题
由 ``POST /tasks/generate`` 承载。

**通用机制（合成必填槽）**：ADR-0104 后无 manifest 再声明必填槽，澄清路径
（追问帧 / DONE 补发 / 落库去重 / 回放气泡）改由 ``required_slots`` 桩把预检
schema 换成合成必填槽来驱动——守护的是槽位引擎本身，将来任何业务声明必填槽都走
同一条路（含 726dba9 的「澄清轮补发 DONE」回归）。
"""
from __future__ import annotations

import asyncio
import json
import uuid
from types import SimpleNamespace

import pytest
from sqlmodel import select

from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    data_event,
    done,
)
from agent_core.runtime import RouteDecision
from app.db.models import Conversation, Message
from app.features.assistant.schemas import AssistantChatReq, CoursewareContext
from app.features.assistant.service import chat


def _caller(role: str, *, user_id: uuid.UUID, teacher_id: uuid.UUID):
    return SimpleNamespace(role=role, user=SimpleNamespace(id=user_id, teacher_id=teacher_id, class_id=None))


class _StubRuntime:
    """桩 runtime：产出一张题卡（DATA 帧）。

    ADR-0104：无 trigger 子意图词，桩只按 business 决策（默认 tasks，模拟真实
    路由对出题问句的落点）；聊天链路纯 LLM 生成，预检恒放行。
    """

    def __init__(self, business: str = "tasks") -> None:
        self.business = business
        self.last_ctx_extra = None

    async def decide(self, signal, *, role: str, deps, history=None) -> RouteDecision:
        return RouteDecision(business=self.business, name="桩业务")

    async def run(self, message, *, role, ctx, deps, business=None, session=None):
        self.last_ctx_extra = ctx.extra
        yield data_event(
            {"subject": "数学", "stem": "1+1=?", "options": ["2"], "answer": "2"},
            extra={"type": "question"},
        )
        yield done(ctx.extra.get("session_id"))


# 合成必填槽 schema（原 tasks generate 意图的必填三件）：ADR-0104 后 manifest 不再
# 声明必填槽，澄清路径的端到端覆盖由它经 ``required_slots`` 桩注入。
_REQUIRED_SLOT_SCHEMA = [
    {"name": "subject", "type": "enum", "required": True,
     "prompt": "请问要出哪个科目？", "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
    {"name": "grade", "type": "int", "required": True,
     "prompt": "几年级？（1-9）", "min": 1, "max": 9, "source": "both"},
    {"name": "qtype", "type": "enum", "required": True,
     "prompt": "要什么题型（选择/填空/计算/解答）？",
     "enum": ["choice", "fill", "calc", "open"], "source": "text"},
]


@pytest.fixture
def required_slots(monkeypatch):
    """把预检 schema 换成合成必填槽，驱动澄清路径（守护通用槽位机制）。"""
    import app.features.assistant.service as svc

    monkeypatch.setattr(
        svc, "_resolve_input_schema", lambda business: list(_REQUIRED_SLOT_SCHEMA)
    )


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


def _clarify_missing(frames: list[str]) -> list[dict]:
    """取本轮澄清帧的 missing_slots（无则空列表）。"""
    for e in _parse(frames):
        clarify = e.get("extra", {}).get("clarify")
        if clarify:
            return clarify["missing_slots"]
    return []


# ── 真实配置：恒放行（不澄清 / 不注入 specs / 不发汇总帧） ──


def test_generation_turn_never_clarifies_or_injects_specs(db):
    """出题问句直接进生成：全 optional schema 恒放行，无澄清帧、无 specs 注入。"""
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
    assert not [e for e in events if e.get("extra", {}).get("clarify")], "不应产出澄清帧"
    # 直接进 rt.run 生成题卡
    assert rt.last_ctx_extra is not None, "应进入 rt.run"
    assert any(e["eventType"] == EVENT_DATA for e in events)
    # 纯 LLM 生成：不往 specs 结构化路径回灌（那是 POST /tasks/generate 的通道）
    assert not (rt.last_ctx_extra or {}).get("specs")
    # 已抽取的槽位按 business 单键落库（跨轮合并仍可用）
    conv = _latest_conv(db, teacher_id=pid)
    assert conv is not None
    assert conv.slots["tasks"]["subject"] == "数学"


def test_two_turns_merge_slots_without_specs(db):
    """两轮都不澄清、不注入 specs；槽位跨轮合并落 ``tasks`` 单键。"""
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
    # 第二轮：只补年级 + 题型
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
    assert not [e for e in events2 if e.get("extra", {}).get("clarify")]
    assert any(e["eventType"] == EVENT_DATA for e in events2)
    assert not (rt.last_ctx_extra or {}).get("specs"), "纯 LLM 生成不注入 specs"
    conv = db.get(Conversation, uuid.UUID(sid))
    assert conv.slots["tasks"]["subject"] == "数学"
    assert conv.slots["tasks"]["grade"] == 3


def test_courseware_context_turn_generates_without_summary_or_specs(db):
    """带课件上下文（subject/grade）+ 文本题型 → 无汇总帧、无 specs，正常出题。"""
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
    assert not any(
        e["eventType"] == EVENT_ASSISTANT_MESSAGE and "已确认规格" in e.get("text", "")
        for e in events
    ), "汇总帧随出题引导一并下线"
    assert any(e["eventType"] == EVENT_DATA for e in events)
    assert not (rt.last_ctx_extra or {}).get("specs")


@pytest.mark.parametrize(
    "business,text",
    [
        # tasks 默认意图（学情 / 名单）：全 optional
        ("tasks", "看看我的错题"),
        ("tasks", "我班有哪些学生"),
        # tutor：question_text 亦为非必填（消息本身就是问题）
        ("tutor", "为什么天空是蓝的"),
    ],
)
def test_non_question_businesses_never_clarify(db, business, text):
    """预检对全部业务生效，但现有 schema 全 optional → 永不追问。"""
    pid = uuid.uuid4()
    rt = _StubRuntime(business=business)
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
    """汇总确认帧已随出题引导下线：tutor 等问答/只读意图更不发（避免噪声）。"""
    pid = uuid.uuid4()
    rt = _StubRuntime(business="tutor")
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
    ), "不应出现「已确认规格」汇总帧"
    assert not (rt.last_ctx_extra or {}).get("specs")


def test_unrelated_followup_does_not_regenerate(db):
    """无关话（如「谢谢」）不按旧规格再出一轮题——纯 LLM 生成下 specs 恒不注入。"""
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
    assert any(e["eventType"] == EVENT_DATA for e in _parse(frames)), "首轮必须生成"
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


def test_other_business_does_not_clobber_tasks_slots(db):
    """tutor 一轮之后，tasks 已收集的槽位仍在（槽位按 business 单键存）。

    回归：flat 单键存 + fill_slots 只搬当前 schema 内的键 → tutor 轮写回的 merged
    不含出题的 grade/qtype，半成形意图被静默清空。ADR-0104 后子意图两本账简化为
    每 business 一键，隔离语义不变。
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
    assert conv.slots["tasks"]["subject"] == "数学"

    tutor_rt = _StubRuntime(business="tutor")
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
    assert conv.slots["tasks"]["subject"] == "数学", "tutor 轮不得冲掉 tasks 槽位"


# ── 通用机制：合成必填槽驱动的澄清路径（ADR-0104 后无 manifest 声明必填槽） ──


def test_missing_slots_yields_clarify_and_no_data_card(db, required_slots):
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
    # 已持久化已知槽位（subject=数学），grade 尚未收集。槽位按 business 单键存放。
    conv = _latest_conv(db, teacher_id=pid)
    assert conv is not None
    assert conv.slots["tasks"]["subject"] == "数学"
    assert "grade" not in (conv.slots["tasks"] or {})


def test_clarify_round_yields_done_and_followup_continues_same_conversation(db, required_slots):
    """澄清轮必须下发 DONE（带 session_id），否则续接会新建会话、把首轮孤立。

    回归（726dba9）：缺槽预检在 ``rt.run`` 之前 return，而 DONE 帧由 ``rt.run`` 的
    finally 产出 → 澄清轮原本收不到 DONE。前端 ``_currentSessionId`` 据此回写，
    缺失则下一句以 sessionId=null 新建会话，表现即「运行详情 / 会话详情都缺第一轮」。
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
                req=_req("三年级出选择题", session_id=sid),
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


def test_partial_fill_asks_only_remaining_required(db, required_slots):
    """只补一个必填槽 → 只追问剩下的：grade 记住了，第二轮只问 qtype。

    边界澄清：qtype 同为必填，故「只回三年级即可续接」不是「只回三年级就生成」——
    按 SPEC「半成形意图跨轮保存、下一轮只需补说缺失项」，已填槽不丢、只问仍缺的。
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
    assert conv.slots["tasks"]["grade"] == 3, "grade 必须跨轮记住"

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


def test_clarify_message_payload_matches_frame_contract(db, required_slots):
    """澄清消息落库 payload 与 extra.clarify 同形（map），不是裸 list。"""
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


def test_clarify_message_text_is_one_shot_guidance(db, required_slots):
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


def test_replay_bubbles_carry_clarify(db, required_slots):
    """回放气泡带 clarify 结构化 extra，且不透传 payload 其余键。

    两轮对话（第一轮缺 grade/qtype → 澄清；第二轮补齐 → 生成）之后调
    ``read_conversation_bubbles``：澄清行的气泡必须带结构化载荷，形状与实时流的
    ``extra`` 一致（同一份解析）。同时断言**白名单**语义——气泡只有
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
    # 第一轮澄清 + 第二轮生成，共 4 条（汇总帧已随出题引导下线）。
    assert [b["role"] for b in bubbles] == [
        "user",
        "assistant",
        "user",
        "assistant",
    ]

    clarify_bubble = bubbles[1]
    assert clarify_bubble["clarify"] is not None
    slots = clarify_bubble["clarify"]["missing_slots"]
    assert [s["name"] for s in slots] == ["grade", "qtype"]
    # 白名单：气泡不带 payload 里的审计面字段
    assert set(clarify_bubble) == {"role", "text", "cards", "clarify", "summary"}
    assert clarify_bubble["summary"] is None

    # 澄清之后的生成行：题卡整帧照常投影（卡片链路不受结构化 extra 影响）
    gen_bubble = bubbles[3]
    assert gen_bubble["cards"], "补齐轮生成的题卡应随气泡回来"
