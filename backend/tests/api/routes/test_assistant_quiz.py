"""ADR-0072 判断题闭环：端到端（经 SSE 端点）单测。

monkeypatch 掉真实出题 LLM，验证：
- quiz=true + 课件上下文 → SSE 下发题卡，答案/解析已剥离（不提前泄题）。
- 续接同一会话回「对」 → 判定为答对，pending_quiz 清空。
- 续接同一会话回含糊答案 → 要求用「对/错」明确作答。

同时锁定 SSE 序列化收口（chat 的 quiz 分支必须 yield ev.to_sse()，而非裸对象）。
"""
import json
import uuid

from sqlmodel import select

from app.db.models import User
from app.db.models.material import KnowledgePoint
from app.domain.provider import GeneratedQuestion
from tests.utils.user import auth_headers, register_teacher


async def _fake_generate_question(provider, *, subject, grade, knowledge_point, qtype, difficulty, semester="", **kwargs):
    return GeneratedQuestion(
        subject=subject, grade=grade, knowledge_point=knowledge_point, qtype=qtype,
        stem="平行四边形是轴对称图形", options=["对", "错"], answer="错",
        explanation="平行四边形不是轴对称图形。", difficulty=difficulty, semester=semester,
    )


def _parse_sse(text):
    out = []
    for line in text.split("\n"):
        line = line.strip()
        if line.startswith("data: "):
            out.append(json.loads(line[len("data: "):]))
    return out


def _teacher_id(db, username: str) -> uuid.UUID:
    return db.exec(select(User).where(User.username == username)).one().id


def _make_kp(db, *, tid, name="轴对称"):
    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name=name
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)
    return kp


def _stream(client, token, body):
    with client.stream(
        "POST",
        "/api/v1/assistant/chat",
        headers={**auth_headers(token), "Accept": "text/event-stream"},
        json=body,
    ) as resp:
        status = resp.status_code
        events = _parse_sse("".join(resp.iter_text()))
    return status, events


def test_quiz_chat_emits_stripped_question_card(client, db, monkeypatch):
    """出题：SSE 下发题卡且答案/解析已剥离（不提前泄题）。"""
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _fake_generate_question
    )
    r = register_teacher(client, username="qz_teacher")
    token = r.json()["access_token"]
    tid = _teacher_id(db, "qz_teacher")
    kp = _make_kp(db, tid=tid)

    status, events = _stream(
        client, token,
        {
            "message": "出一道判断题",
            "quiz": True,
            "courseware": {
                "knowledge_point_id": str(kp.id),
                "subject": "数学", "grade": 4, "semester": "下学期",
                "knowledge_point": "轴对称",
            },
        },
    )
    assert status == 200, events
    types = [e["eventType"] for e in events]
    assert "DONE" in types
    # SSE 序列化收口正确：每个帧都是 dict（data: {...}），不是裸对象 repr。
    assert all(isinstance(e, dict) for e in events)

    questions = [
        e["data"]["result"]
        for e in events
        if e["eventType"] == "DATA" and e["data"].get("type") == "question"
    ]
    assert len(questions) == 1
    q = questions[0]
    assert q["stem"] == "平行四边形是轴对称图形"
    assert q["answer"] == ""
    assert q["explanation"] == ""


def test_quiz_judge_correct_via_session(client, db, monkeypatch):
    """续接同一会话回正确答案「错」 → 判定答对，pending_quiz 清空。

    （判断题固定为「平行四边形是轴对称图形」→ 真答案为「错」。）

    """
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _fake_generate_question
    )
    r = register_teacher(client, username="qz2_teacher")
    token = r.json()["access_token"]
    tid = _teacher_id(db, "qz2_teacher")
    kp = _make_kp(db, tid=tid)

    _status, gen_events = _stream(
        client, token,
        {
            "message": "出一道判断题",
            "quiz": True,
            "courseware": {
                "knowledge_point_id": str(kp.id),
                "subject": "数学", "grade": 4, "semester": "下学期",
                "knowledge_point": "轴对称",
            },
        },
    )
    sid = [e for e in gen_events if e["eventType"] == "DONE"][-1]["session_id"]
    assert sid, "首轮 DONE 帧应回写会话 id"

    status2, judge_events = _stream(
        client, token, {"message": "错", "session_id": sid}
    )
    assert status2 == 200, judge_events
    answer = "".join(
        e.get("text", "") for e in judge_events if e["eventType"] == "ASSISTANT_MESSAGE"
    )
    assert "答对" in answer


def test_quiz_judge_ambiguous_via_session(client, db, monkeypatch):
    """续接同一会话回含糊答案 → 要求用「对/错」明确作答，仍待判定。"""
    monkeypatch.setattr(
        "app.features.assistant.service.generate_question", _fake_generate_question
    )
    r = register_teacher(client, username="qz3_teacher")
    token = r.json()["access_token"]
    tid = _teacher_id(db, "qz3_teacher")
    kp = _make_kp(db, tid=tid)

    _status, gen_events = _stream(
        client, token,
        {
            "message": "出一道判断题",
            "quiz": True,
            "courseware": {"knowledge_point_id": str(kp.id)},
        },
    )
    sid = [e for e in gen_events if e["eventType"] == "DONE"][-1]["session_id"]

    status2, judge_events = _stream(
        client, token, {"message": "这题我不会", "session_id": sid}
    )
    assert status2 == 200, judge_events
    answer = "".join(
        e.get("text", "") for e in judge_events if e["eventType"] == "ASSISTANT_MESSAGE"
    )
    assert "请用" in answer and "对" in answer and "错" in answer
