"""ADR-0067 课件练习：助手上下文、guide/tutor 分流与零任务副作用。"""
from __future__ import annotations

import json
import uuid
from uuid import UUID

from sqlmodel import Session, select

from app.core.db import engine
from app.db.models import Conversation, Task, TaskQuestion, User
from app.features.assistant import service as assistant_service
from tests.utils.fake_provider import FakeLLMProvider
from tests.utils.user import auth_headers, login, register_teacher


def _teacher(client) -> tuple[str, UUID]:
    username = f"cw_practice_{uuid.uuid4().hex[:8]}"
    registered = register_teacher(client, username=username)
    assert registered.status_code in (200, 201), registered.text
    token = login(client, username, "pw123456").json()["access_token"]
    with Session(engine) as session:
        teacher = session.exec(select(User).where(User.username == username)).one()
        teacher_id = teacher.id
    return token, teacher_id


def _parse_sse(text: str) -> list[dict]:
    return [
        json.loads(line[6:])
        for line in text.splitlines()
        if line.startswith("data: ")
    ]


def _stream(client, token: str, message: str, *, extra: dict | None = None):
    body = {"message": message, **(extra or {})}
    with client.stream(
        "POST",
        "/api/v1/assistant/chat",
        headers={**auth_headers(token), "Accept": "text/event-stream"},
        json=body,
    ) as response:
        return response.status_code, _parse_sse("".join(response.iter_text()))


def _task_counts() -> tuple[int, int]:
    with Session(engine) as session:
        return (
            len(session.exec(select(Task)).all()),
            len(session.exec(select(TaskQuestion)).all()),
        )


def _courseware() -> dict:
    return {
        "courseware": {
            "courseware_id": str(uuid.uuid4()),
            "section_id": "practice-1",
            "knowledge_point": "轴对称图形",
            "subject": "数学",
            "grade": 4,
            "semester": "下学期",
        }
    }


def test_courseware_question_routes_to_guide_and_never_creates_task(
    client, fake_llm, monkeypatch
):
    """打统一端点：课件出题转 guide，答错转 tutor，且全程零 Task/TaskQuestion。"""
    token, teacher_id = _teacher(client)
    before = _task_counts()
    context = _courseware()

    status, question_events = _stream(
        client,
        token,
        "请为当前课堂练习出一道选择题",
        extra=context,
    )
    assert status == 200, question_events
    routed = [
        event.get("text", "")
        for event in question_events
        if event["eventType"] == "THINKING"
        and event.get("extra", {}).get("routing")
    ]
    assert any("任务引导" in text for text in routed), routed
    question = "".join(
        event.get("text", "")
        for event in question_events
        if event["eventType"] == "ASSISTANT_MESSAGE"
    )
    assert "测试题的题干" in question
    assert "答案" not in question and "解析" not in question
    assert not any(event["eventType"] == "DATA" for event in question_events)

    done = [event for event in question_events if event["eventType"] == "DONE"]
    session_id = done[-1]["session_id"]
    captured: dict = {}

    async def _hint_stream(**kwargs):
        captured.update(kwargs)
        yield "先观察图形两侧能否沿同一条直线完全重合。"

    monkeypatch.setattr(fake_llm, "tutor_stream", _hint_stream)
    status, hint_events = _stream(
        client,
        token,
        "学生刚才答错了，请给第 1 级提示帮助他继续思考，不要直接说答案。",
        extra={**context, "session_id": session_id},
    )
    assert status == 200, hint_events
    routed = [
        event.get("text", "")
        for event in hint_events
        if event["eventType"] == "THINKING"
        and event.get("extra", {}).get("routing")
    ]
    assert any("伴学答疑" in text for text in routed), routed
    assert captured["subject"] == "数学"
    assert captured["grade"] == 4
    assert captured["knowledge_point"] == "轴对称图形"
    assert "第1级只提醒观察方向" in captured["context"]
    assert "不得直接给出答案" in captured["context"]
    assert _task_counts() == before

    with Session(engine) as session:
        conversation = session.get(Conversation, UUID(session_id))
        assert conversation is not None
        assert conversation.teacher_id == teacher_id
        assert conversation.student_id is None
        assert conversation.kind == "guide"


class _NoModelProvider(FakeLLMProvider):
    @property
    def configured(self) -> bool:
        return False


def test_courseware_question_without_model_has_explicit_message(client, monkeypatch):
    token, _teacher_id = _teacher(client)
    monkeypatch.setattr(
        assistant_service,
        "build_provider",
        lambda engine=None: _NoModelProvider(),
    )

    status, events = _stream(
        client,
        token,
        "请为当前课堂练习出一道选择题",
        extra=_courseware(),
    )
    assert status == 200, events
    text = "".join(
        event.get("text", "")
        for event in events
        if event["eventType"] == "ASSISTANT_MESSAGE"
    )
    assert "未配置模型" in text
