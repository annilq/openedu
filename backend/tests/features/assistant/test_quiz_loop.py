"""ADR-0072：判断题闭环（出题-判定-引导）单测。

出题复用 question 管线（monkeypatch 掉真实 LLM），判定与引导是确定性逻辑、不靠 LLM：

- 出题：生成判断题 → 题卡剥离答案/解析后下发（不提前泄题）→ 写 pending_quiz。
- 判定：用户自然语言 yes/no → 比对已知答案；答对鼓励、答错分级支架引导（不泄答案）、
  两次仍错讲解；求讲解 / 含糊回答走各自分支。
"""
import asyncio
import uuid
from collections.abc import AsyncIterator

from agent_core.protocol import (
    EVENT_ASSISTANT_MESSAGE,
    EVENT_DATA,
    EVENT_DONE,
    EVENT_ERROR,
    EVENT_RUN_STARTED,
)
from app.db.models import Conversation
from app.db.models.material import KnowledgePoint
from app.domain.provider import GeneratedQuestion
from app.features.assistant.schemas import AssistantChatReq, CoursewareContext
from app.features.assistant.service import (
    _is_explain_request,
    _judge_answer_bool,
    _parse_yes_no,
    _quiz_generate_stream,
    _quiz_judge_stream,
)

# ── 确定性词典（不靠 LLM 的判定核心，单独锁死） ────────────────────────────────


def test_parse_yes_no_true_and_false():
    assert _parse_yes_no("对") is True
    assert _parse_yes_no("是的，正确") is True
    assert _parse_yes_no("错") is False
    assert _parse_yes_no("不对，应该是错的") is False  # false 词优先，不被 true 词误判
    assert _parse_yes_no("这题我不会") is None  # 无明确信号


def test_judge_answer_bool_normalizes():
    assert _judge_answer_bool("对") is True
    assert _judge_answer_bool("错") is False
    assert _judge_answer_bool("错误") is False
    assert _judge_answer_bool("") is True  # 兜底收口为真，避免答案判定整体崩坏


def test_is_explain_request():
    assert _is_explain_request("讲解一下") is True
    assert _is_explain_request("为什么是错的") is True
    assert _is_explain_request("请出一道题") is False


# ── 出题 + 判定闭环（monkeypatch 掉真实 LLM） ──────────────────────────────────


async def _fake_generate_question(provider, *, subject, grade, knowledge_point, qtype, difficulty, semester="", **kwargs):
    """替身：恒定返回一道「平行四边形是轴对称图形 → 错」的判断题。"""
    return GeneratedQuestion(
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        stem="平行四边形是轴对称图形",
        options=["对", "错"],
        answer="错",
        explanation="平行四边形两组对边平行且相等，但不是轴对称图形。",
        difficulty=difficulty,
        semester=semester,
    )


async def _drain(gen: AsyncIterator) -> list:
    frames: list = []
    async for f in gen:
        frames.append(f)
    return frames


def _teacher_id() -> uuid.UUID:
    return uuid.uuid4()


def _conv(db, *, teacher_id, conv_id: uuid.UUID) -> Conversation:
    conv = Conversation(
        id=conv_id,
        kind="agent",
        teacher_id=teacher_id,
        student_id=None,
        model=None,
        title="出题",
        status="running",
    )
    db.add(conv)
    db.commit()
    return conv


class _ConfiguredProvider:
    """测试桩：模拟「已配置可用模型」的 provider（真实 GenkitProvider 的极小替身）。"""

    configured = True


def test_quiz_generate_strips_answer_and_writes_pending(db, monkeypatch):
    """出题：题卡剥离答案/解析后下发（不提前泄题），pending_quiz 写入正确答案与元信息。"""
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _fake_generate_question
    )
    tid = _teacher_id()
    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name="轴对称"
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)

    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    req = AssistantChatReq(
        message="出一道判断题",
        courseware=CoursewareContext(knowledge_point_id=kp.id),
        quiz=True,
    )

    frames = asyncio.run(
        _drain(
            _quiz_generate_stream(
                session=db, conv_id=conv_id, req=req, teacher_id=tid,
                provider=_ConfiguredProvider(),
            )
        )
    )
    types = [f.eventType for f in frames]
    assert EVENT_RUN_STARTED in types
    assert EVENT_DONE in types
    assert frames[-1].session_id == str(conv_id)

    data_frames = [f for f in frames if f.eventType == EVENT_DATA]
    assert len(data_frames) == 1
    card = data_frames[0].data["result"]
    assert data_frames[0].data["type"] == "question"
    # 题面照发，但答案 / 解析 / 推理被剥离，不能提前泄题。
    assert card["stem"] == "平行四边形是轴对称图形"
    assert card["options"] == ["对", "错"]
    assert card["answer"] == ""
    assert card["explanation"] == ""
    assert card["reasoning"] == ""

    # 正确答案布尔 + 元信息落 pending_quiz，待判定分支消费。
    conv = db.get(Conversation, conv_id)
    pending = conv.pending_quiz
    assert pending["answer"] is False
    assert pending["name"] == "轴对称"
    assert pending["attempts"] == 0
    assert pending["answer_text"] == "错"
    assert pending["explanation"]


class _UnconfiguredProvider:
    """测试桩：模拟「未配置可用模型」的 provider（configured=False）。"""

    configured = False


def test_quiz_generate_unconfigured_provider_emits_hint(db):
    """未配置模型：出题入口应下发干净的「未配置模型」提示，而非放出去撞 401。"""
    tid = _teacher_id()
    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name="轴对称"
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)

    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    req = AssistantChatReq(
        message="出一道判断题",
        courseware=CoursewareContext(knowledge_point_id=kp.id),
        quiz=True,
    )

    frames = asyncio.run(
        _drain(
            _quiz_generate_stream(
                session=db, conv_id=conv_id, req=req, teacher_id=tid,
                provider=_UnconfiguredProvider(),
            )
        )
    )
    types = [f.eventType for f in frames]
    assert EVENT_RUN_STARTED in types
    assert EVENT_DONE in types
    text = "".join(f.text for f in frames if f.eventType == EVENT_ASSISTANT_MESSAGE)
    assert "尚未配置可用的模型" in text
    # 未配置时不应触达 generate_question，也不应产出题卡。
    assert not any(f.eventType == EVENT_DATA for f in frames)


async def _boom_generate_question(provider, *, subject, grade, knowledge_point, qtype, difficulty, semester="", **kwargs):
    """替身：恒定抛 ProviderRequestError（模拟 API key 失效 / 厂商拒绝）。"""
    from agent_core.errors import ProviderRequestError

    raise ProviderRequestError("auth failed", kind="auth")


def test_quiz_generate_provider_failure_surfaced_as_error_frame(db, monkeypatch):
    """provider 鉴权失败：必须转成 SSE ERROR 帧，不得让异常穿透生成器导致流被截断。"""
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _boom_generate_question
    )
    tid = _teacher_id()
    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name="轴对称"
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)

    conv_id = uuid.uuid4()
    _conv(db, teacher_id=tid, conv_id=conv_id)
    req = AssistantChatReq(
        message="出一道判断题",
        courseware=CoursewareContext(knowledge_point_id=kp.id),
        quiz=True,
    )

    frames = asyncio.run(
        _drain(
            _quiz_generate_stream(
                session=db, conv_id=conv_id, req=req, teacher_id=tid,
                provider=_ConfiguredProvider(),
            )
        )
    )
    types = [f.eventType for f in frames]
    assert EVENT_RUN_STARTED in types
    assert EVENT_DONE in types
    error_frames = [f for f in frames if f.eventType == EVENT_ERROR]
    assert len(error_frames) == 1
    assert error_frames[0].code == "PROVIDER_ERROR"
    assert "API Key" in error_frames[0].message  # 策展提示，不泄露原始报文


def _pending_fixture(db, *, conv, answer=True) -> dict:
    pending = {
        "answer": answer,
        "subject": "数学", "grade": 4, "semester": "下学期", "name": "轴对称",
        "stem": "平行四边形是轴对称图形", "options": ["对", "错"],
        "answer_text": "对" if answer else "错",
        "explanation": "（解析）", "attempts": 0,
    }
    conv.pending_quiz = pending
    db.add(conv)
    db.commit()
    return pending


def test_quiz_judge_correct_clears_pending(db):
    """答对：鼓励文案，pending_quiz 清空。"""
    tid = _teacher_id()
    conv_id = uuid.uuid4()
    conv = _conv(db, teacher_id=tid, conv_id=conv_id)
    _pending_fixture(db, conv=conv, answer=True)

    frames = asyncio.run(
        _drain(_quiz_judge_stream(session=db, conv=conv, conv_id=conv_id, message="对"))
    )
    text = "".join(
        f.text for f in frames if f.eventType == EVENT_ASSISTANT_MESSAGE
    )
    assert "答对" in text
    assert db.get(Conversation, conv_id).pending_quiz is None


def test_quiz_judge_wrong_first_attempt_keeps_pending_and_does_not_reveal(db):
    """答错（首次）：分级支架引导，pending_quiz 保留且**不泄答案**。"""
    tid = _teacher_id()
    conv_id = uuid.uuid4()
    conv = _conv(db, teacher_id=tid, conv_id=conv_id)
    _pending_fixture(db, conv=conv, answer=True)  # 正确应为「对」

    frames = asyncio.run(
        _drain(_quiz_judge_stream(session=db, conv=conv, conv_id=conv_id, message="错"))
    )
    text = "".join(
        f.text for f in frames if f.eventType == EVENT_ASSISTANT_MESSAGE
    )
    assert "再想想" in text
    # 首次答错不揭示答案：泄露答案的固定句式是「正确的判断是「X」」，
    # 这里必须不出现；注意知识点名「轴对称」含「对」字，不能用子串「对」误判。
    assert "正确的判断" not in text
    pending = db.get(Conversation, conv_id).pending_quiz
    assert pending is not None and pending["attempts"] == 1


def test_quiz_judge_wrong_twice_reveals_answer(db):
    """答错两次：直接讲解并揭示答案 + 解析，pending_quiz 清空。"""
    tid = _teacher_id()
    conv_id = uuid.uuid4()
    conv = _conv(db, teacher_id=tid, conv_id=conv_id)
    _pending_fixture(db, conv=conv, answer=True)

    asyncio.run(
        _drain(_quiz_judge_stream(session=db, conv=conv, conv_id=conv_id, message="错"))
    )
    frames2 = asyncio.run(
        _drain(_quiz_judge_stream(session=db, conv=conv, conv_id=conv_id, message="错"))
    )
    text2 = "".join(
        f.text for f in frames2 if f.eventType == EVENT_ASSISTANT_MESSAGE
    )
    assert "正确的判断" in text2  # 揭示答案
    assert "（解析）" in text2  # 揭示解析
    assert db.get(Conversation, conv_id).pending_quiz is None


def test_quiz_judge_ambiguous_prompts_again(db):
    """含糊回答：要求用「对/错」明确作答，不判定。"""
    tid = _teacher_id()
    conv_id = uuid.uuid4()
    conv = _conv(db, teacher_id=tid, conv_id=conv_id)
    _pending_fixture(db, conv=conv, answer=True)

    frames = asyncio.run(
        _drain(_quiz_judge_stream(session=db, conv=conv, conv_id=conv_id, message="这题我不会"))
    )
    text = "".join(
        f.text for f in frames if f.eventType == EVENT_ASSISTANT_MESSAGE
    )
    assert "请用" in text and "对" in text and "错" in text
    assert db.get(Conversation, conv_id).pending_quiz is not None  # 仍待判定


def test_quiz_judge_explain_reveals_and_clears(db):
    """求讲解：揭示答案 + 解析，pending_quiz 清空。"""
    tid = _teacher_id()
    conv_id = uuid.uuid4()
    conv = _conv(db, teacher_id=tid, conv_id=conv_id)
    _pending_fixture(db, conv=conv, answer=True)

    frames = asyncio.run(
        _drain(_quiz_judge_stream(session=db, conv=conv, conv_id=conv_id, message="讲解一下"))
    )
    text = "".join(
        f.text for f in frames if f.eventType == EVENT_ASSISTANT_MESSAGE
    )
    assert "正确的判断" in text
    assert "（解析）" in text
    assert db.get(Conversation, conv_id).pending_quiz is None
