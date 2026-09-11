"""复习作答写路径测试（#3 深度保证书，窄接口、绕开 HTTP 与真 LLM）。

直接调 ``review_service.submit_answer``，验证 due 守卫与归属校验已提升为领域异常
（而非 router 里的 HTTPException）；并把编排移回 router 会让本文件无法成立。
"""
import uuid
from datetime import UTC, datetime, timedelta

from sqlmodel import Session, select

from app.db.models import AnswerRecord, Question, WrongQuestion
from app.domain import Grader
from app.features.review import service as review_service
from app.features.review.schemas import ReviewAnswerSubmit


def _make_entities(db: Session, *, due_in_past: bool = True, stage: int = 0):
    q = Question(
        subject="数学",
        grade=2,
        knowledge_point="加法",
        qtype="calc",
        stem="1 + 1 = ?",
        options=None,
        answer="2",
        explanation="1 加 1 等于 2。",
    )
    db.add(q)
    db.commit()
    db.refresh(q)
    wq = WrongQuestion(
        child_id=uuid.uuid4(),
        question_id=q.id,
        review_stage=stage,
        due_at=(
            datetime.now(UTC) - timedelta(minutes=5)
            if due_in_past
            else datetime.now(UTC) + timedelta(days=1)
        ),
        wrong_count=1,
        last_wrong_at=datetime.now(UTC),
    )
    db.add(wq)
    db.commit()
    db.refresh(wq)
    return q, wq


def _stub_grader(monkeypatch, *, correct: bool = True):
    # 批改逻辑不依赖真 LLM：直接返回桩结果。
    monkeypatch.setattr(
        Grader,
        "grade",
        lambda self, question, student_answer: {
            "correct": correct,
            "score": 1.0 if correct else 0.0,
        },
    )
    # build_ai_provider 在测试环境可能触发 env 缺失，桩掉避免构造真实 provider。
    monkeypatch.setattr(review_service, "build_ai_provider", lambda: None)


def test_submit_answer_not_due_rejected(db: Session, monkeypatch):
    _q, wq = _make_entities(db, due_in_past=False)
    _stub_grader(monkeypatch)
    submit = ReviewAnswerSubmit(wrong_question_id=wq.id, student_answer="2")
    try:
        review_service.submit_answer(session=db, child_id=wq.child_id, submit=submit)
        assert False, "expected ReviewNotDue"
    except review_service.ReviewNotDue:
        pass


def test_submit_answer_wrong_owner_404(db: Session, monkeypatch):
    _q, wq = _make_entities(db, due_in_past=True)
    _stub_grader(monkeypatch)
    submit = ReviewAnswerSubmit(wrong_question_id=wq.id, student_answer="2")
    try:
        review_service.submit_answer(session=db, child_id=uuid.uuid4(), submit=submit)
        assert False, "expected ReviewNotFound"
    except review_service.ReviewNotFound:
        pass


def test_submit_answer_happy_path_advances(db: Session, monkeypatch):
    _q, wq = _make_entities(db, due_in_past=True)
    _stub_grader(monkeypatch)
    submit = ReviewAnswerSubmit(wrong_question_id=wq.id, student_answer="2")

    result = review_service.submit_answer(session=db, child_id=wq.child_id, submit=submit)

    assert result.correct is True
    assert result.score == 1.0
    refreshed = db.get(WrongQuestion, wq.id)
    assert refreshed.review_stage == 1  # 遗忘曲线推进
    assert refreshed.due_at is not None
    # 作答记录落库，来源标记为 review
    rec = db.exec(
        select(AnswerRecord).where(
            AnswerRecord.question_id == wq.question_id,
            AnswerRecord.source == "review",
        )
    ).first()
    assert rec is not None
