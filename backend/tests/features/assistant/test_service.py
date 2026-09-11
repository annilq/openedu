"""assistant.chat 服务层单测（架构深化 #2 存活测试）。

不接 HTTP、不接真实 LLM：注入桩 ``AgentRuntime``，直接驱动 ``chat`` 的窄 3 参接口，
证明「事件流 → 折叠 → 落库（Message 轨迹 + TutorLog 副作用）」整条编排可达且正确。

若有人把编排重新漏回 router，这两条用例会立刻无法成立——它们是深度保证书。
"""
import asyncio
import uuid
from collections.abc import AsyncIterator
from types import SimpleNamespace

from sqlmodel import select

from agent_core.protocol import assistant_message, done, tool_call, tool_result
from agent_core.runtime import RouteDecision
from app.db.models import Conversation, Message, TutorLog
from app.features.assistant.schemas import AssistantChatReq
from app.features.assistant.service import chat


def _caller(role: str, *, user_id: uuid.UUID, parent_id: uuid.UUID, grade: int = 0):
    """轻量 caller 桩（不触 HTTP）：服务只读 role / user.id / user.parent_id / user.grade。"""
    return SimpleNamespace(role=role, user=SimpleNamespace(id=user_id, parent_id=parent_id, grade=grade))


class _StubRuntime:
    """桩 runtime：``decide`` 给固定业务键，``run`` 产出可判定序列（DONE 带 session_id）。"""

    def __init__(self, business: str | None, name: str | None) -> None:
        self._business = business
        self._name = name

    async def decide(self, message: str, *, role: str, deps) -> RouteDecision:
        return RouteDecision(business=self._business, name=self._name)

    async def run(
        self, message: str, *, role: str, ctx, deps, business=None, session=None
    ) -> AsyncIterator:
        yield tool_call("calc", label="计算", args={"a": 23, "b": 45})
        yield tool_result("calc", {"sum": 68})
        yield assistant_message("答案是68")
        yield done(ctx.extra.get("session_id"))


def _req(message: str) -> AssistantChatReq:
    return AssistantChatReq(message=message)


async def _drain(chat_coro) -> list[str]:
    # ``chat`` 是 async def，返回异步生成器；先 await 拿到生成器再迭代。
    gen = await chat_coro
    frames: list[str] = []
    async for frame in gen:
        frames.append(frame)
    return frames


def _latest_conversation(session, *, parent_id=None, child_id=None):
    stmt = select(Conversation)
    if parent_id is not None:
        stmt = stmt.where(Conversation.parent_id == parent_id)
    if child_id is not None:
        stmt = stmt.where(Conversation.child_id == child_id)
    conv = session.exec(stmt.order_by(Conversation.created_at.desc())).first()
    assert conv is not None, "会话应已落库"
    msgs = list(
        session.exec(
            select(Message).where(Message.conversation_id == conv.id).order_by(Message.turn.asc())
        ).all()
    )
    return conv, msgs


def test_chat_folds_stream_into_message_trace(db):
    """happy-path：tool_call/result + 助手输出折叠为 5 步 Message 轨迹，会话置 done。"""
    pid = uuid.uuid4()
    caller = _caller("parent", user_id=pid, parent_id=pid)

    frames = asyncio.run(
        _drain(chat(caller=caller, req=_req("23+45"), session=db, runtime=_StubRuntime("tutor", "伴学答疑")))
    )
    assert any("DONE" in f for f in frames), "应产出 DONE 帧"

    conv, msgs = _latest_conversation(db, parent_id=pid)
    assert (conv.kind, conv.status) == ("tutor", "done")
    assert [m.step for m in msgs] == ["input", "routing", "tool_call", "tool_result", "output"]
    assert msgs[-1].content == "答案是68"
    # tool_call 落库内容取 ev.label or ev.tool（service.py:265），桩给 label="计算"
    assert msgs[2].content == "计算"


def test_child_tutor_chat_writes_tutor_log(db):
    """ADR-008 副作用：娃娃伴学落 TutorLog（家长可见 + 每日上限计数），且未拦截。"""
    pid = uuid.uuid4()
    cid = uuid.uuid4()
    caller = _caller("child", user_id=cid, parent_id=pid, grade=3)

    asyncio.run(
        _drain(chat(caller=caller, req=_req("23+45"), session=db, runtime=_StubRuntime("tutor", "伴学答疑")))
    )

    logs = db.exec(select(TutorLog).where(TutorLog.child_id == cid)).all()
    assert len(logs) == 1, "娃娃伴学应落一条 TutorLog"
    assert logs[0].question == "23+45"
    assert logs[0].blocked is False
