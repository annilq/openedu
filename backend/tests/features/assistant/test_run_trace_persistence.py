"""ADR-0088 ticket 01：``Message`` 步级 usage / latency / model / safety 落库。

``Message`` 的 ``model`` / ``usage`` / ``latency_ms`` / ``input_safe`` / ``output_safe`` /
``blocked`` / ``block_reason`` 七列自 ADR-0022 起就在表里，但落库路径从未赋值——运行
轨迹页要展示「哪一步最费 token / 最慢 / 被拦」，列是空的就只能是空面板。

本文件是那条断言的存活测试，被测缝是 ``service.chat`` 的**落库路径**（桩 runtime 注入，
不接 HTTP、不接真实模型）：

- generation 步与 tool 步的 ``model`` / ``usage`` / ``latency_ms`` 非空；
- 步级 ``usage`` 能 ``GROUP BY conversation_id`` 上推出会话总成本（故不建会话级汇总列）；
- 学生面按实际安全判定写 ``input_safe`` / ``output_safe``，拦截步写 ``blocked`` / ``block_reason``。
"""
from __future__ import annotations

import asyncio
import uuid
from types import SimpleNamespace

from sqlmodel import Session, func, select

from agent_core.protocol import assistant_message, done, error, tool_call, tool_result
from agent_core.runtime import RouteDecision
from app.core.crypto import encrypt
from app.db.models import Conversation, Message, ModelConfig
from app.features.assistant.schemas import AssistantChatReq
from app.features.assistant.service import chat

# 桩 runtime 每段的可判定延迟：latency_ms 断言要求「睡过就一定 >0」，
# 恒 0 的计时器会让这条断言形同虚设（拿 0 当实测值）。
_PAUSE = 0.02

# 命中输入闸门的提问（非学习类主题，见 app.domain.safety._OFFTOPIC_HINTS）。
_UNSAFE_QUESTION = "哪里可以买到毒品"


class _StubRuntime:
    """桩 runtime：一次工具调用 + 一段正文，工具执行与生成各带一段可判定延迟。"""

    def __init__(
        self,
        business: str = "tutor",
        *,
        unsafe: bool = False,
        answer: str = "这道题的答案是 68，先算个位再算十位。",
    ) -> None:
        self._business = business
        self._unsafe = unsafe
        self._answer = answer

    async def decide(self, message, *, role, deps, history=None) -> RouteDecision:
        return RouteDecision(business=self._business, name="伴学答疑")

    async def run(
        self, message, *, role, ctx, deps, business=None, session=None
    ):
        if self._unsafe:
            yield error("输入含不适当内容，已拒绝。", code="INPUT_UNSAFE")
            yield done(ctx.extra.get("session_id"))
            return
        await asyncio.sleep(_PAUSE)  # 模型产出工具请求
        yield tool_call("calc", label="计算", args={"a": 23, "b": 45})
        await asyncio.sleep(_PAUSE)  # 工具执行
        yield tool_result("calc", {"sum": 68})
        yield assistant_message(self._answer)
        await asyncio.sleep(_PAUSE)  # 生成收尾
        yield done(ctx.extra.get("session_id"))


def _caller(role: str, *, user_id: uuid.UUID, teacher_id: uuid.UUID | None):
    return SimpleNamespace(
        role=role,
        user=SimpleNamespace(id=user_id, teacher_id=teacher_id, class_id=None),
    )


def _seed_default_model(db: Session, teacher_id: uuid.UUID) -> None:
    """给教师配一个默认模型：落库的 model 应是**解析后**的引擎模型串。"""
    db.add(
        ModelConfig(
            teacher_id=teacher_id,
            provider="openai_compat",
            model_name="gpt-4o-mini",
            api_key_enc=encrypt("sk-test-key"),
            base_url=None,
            label="gpt-4o-mini",
            is_default=True,
        )
    )
    db.commit()


async def _drain(chat_coro) -> list[str]:
    gen = await chat_coro
    return [frame async for frame in gen]


def _steps_of(db: Session, conv_id: uuid.UUID) -> dict[str, Message]:
    msgs = list(
        db.exec(
            select(Message)
            .where(Message.conversation_id == conv_id)
            .order_by(Message.turn.asc())
        ).all()
    )
    return {m.step: m for m in msgs}


def _run(
    db: Session,
    *,
    role: str = "teacher",
    runtime=None,
    message: str = "23+45 怎么算？",
):
    pid = uuid.uuid4()
    caller = _caller(role, user_id=pid, teacher_id=pid)
    if role == "teacher":
        _seed_default_model(db, pid)
    asyncio.run(
        _drain(
            chat(
                caller=caller,
                req=AssistantChatReq(message=message),
                session=db,
                runtime=runtime or _StubRuntime(),
            )
        )
    )
    conv = db.exec(select(Conversation).where(Conversation.teacher_id == pid)).one()
    return conv


def test_generation_and_tool_steps_persist_usage_latency_model(db: Session):
    """generation 步与 tool 步的 model / usage / latency_ms 必须非空且自洽。"""
    conv = _run(db)
    steps = _steps_of(db, conv.id)

    for step in ("tool_call", "output"):
        m = steps[step]
        assert m.model == "openai/gpt-4o-mini", f"{step} 步未记下所用模型"
        assert m.usage is not None, f"{step} 步未记下 token"
        assert set(m.usage) == {"prompt", "completion", "total"}
        assert m.usage["total"] == m.usage["prompt"] + m.usage["completion"]
        assert m.usage["total"] > 0
        # 桩里明确睡过 _PAUSE：证明 latency_ms 是实测值而非恒 0 的占位。
        assert m.latency_ms >= 1, f"{step} 步 latency_ms 应为实测毫秒数"

    # 工具步的 token 记在**调用**行：结果行只是回灌，重复记账会让会话总成本翻倍。
    assert steps["tool_call"].usage["completion"] > 0
    assert steps["tool_result"].usage is None


def test_session_token_cost_is_derivable_from_step_usage(db: Session):
    """步级 usage 可 GROUP BY conversation_id 上推出会话总成本（不建汇总列）。"""
    conv = _run(db)
    steps = _steps_of(db, conv.id)

    rows = db.exec(
        select(
            Message.conversation_id,
            func.sum(func.json_extract(Message.usage, "$.total")),
        )
        .where(Message.conversation_id == conv.id)
        .group_by(Message.conversation_id)
    ).all()
    assert len(rows) == 1
    grouped_total = rows[0][1]

    expected = sum(
        (m.usage or {}).get("total", 0) for m in steps.values()
    )
    assert grouped_total == expected
    # 总成本确实由「生成 + 工具调用」两步构成，不是某一步的巧合。
    assert grouped_total == (
        steps["output"].usage["total"] + steps["tool_call"].usage["total"]
    )


def test_student_blocked_input_persists_safety_flags(db: Session):
    """学生面被输入闸门拦下 → input_safe=False、blocked=True、block_reason 有值。"""
    conv = _run(
        db,
        role="student",
        runtime=_StubRuntime(unsafe=True),
        message=_UNSAFE_QUESTION,
    )
    steps = _steps_of(db, conv.id)

    assert steps["input"].input_safe is False
    assert steps["input"].blocked is True
    assert steps["input"].block_reason
    # 拦截步同样带着标记，排障时才能定位「哪一步被拦」。
    assert steps["output"].input_safe is False
    assert steps["output"].blocked is True
    assert steps["output"].block_reason


def test_student_unsafe_output_persists_output_safe_false(db: Session):
    """学生面输出命中敏感词 → output_safe=False 并记下原因（ADR-008 输出闸门）。"""
    conv = _run(
        db,
        role="student",
        runtime=_StubRuntime(answer="这段里混进了色情内容，不能讲。"),
    )
    steps = _steps_of(db, conv.id)

    assert steps["output"].input_safe is True
    assert steps["output"].output_safe is False
    assert steps["output"].blocked is True
    assert steps["output"].block_reason
