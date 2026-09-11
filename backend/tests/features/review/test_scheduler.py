"""遗忘曲线状态机单一事实源测试（#4 深度保证书，纯 domain 无 LLM/HTTP）。

若有人把状态机移回 ``review/repository`` 或复制回 ``tasks/repository``，
本条会直接失败。
"""
import uuid
from datetime import UTC, datetime, timedelta

from sqlmodel import Session

from app.db.models import WrongQuestion
from app.domain.review_scheduler import REVIEW_INTERVALS_DAYS, apply_review_outcome


def _make_wq(*, stage: int = 0, wrong_count: int = 1) -> WrongQuestion:
    return WrongQuestion(
        child_id=uuid.uuid4(),
        question_id=uuid.uuid4(),
        review_stage=stage,
        due_at=datetime.now(UTC),
        wrong_count=wrong_count,
        last_wrong_at=datetime.now(UTC),
    )


def test_correct_advances_stage(db: Session):
    wq = _make_wq(stage=0)
    db.add(wq)
    db.commit()
    db.refresh(wq)

    out = apply_review_outcome(session=db, wq=wq, correct=True)

    assert out is not None
    assert out.review_stage == 1
    assert out.due_at is not None


def test_final_correct_graduates(db: Session):
    last = len(REVIEW_INTERVALS_DAYS) - 1
    wq = _make_wq(stage=last)
    db.add(wq)
    db.commit()
    db.refresh(wq)

    out = apply_review_outcome(session=db, wq=wq, correct=True)

    assert out is None  # 末位答对毕业删除
    assert db.get(WrongQuestion, wq.id) is None


def test_wrong_resets_timer(db: Session):
    wq = _make_wq(stage=2, wrong_count=3)
    db.add(wq)
    db.commit()
    db.refresh(wq)

    out = apply_review_outcome(session=db, wq=wq, correct=False)

    assert out is not None
    assert out.review_stage == 0
    assert out.wrong_count == 4
    assert out.due_at is not None
    # 重置回首档 1 天
    assert out.due_at <= datetime.now(UTC) + timedelta(days=1, minutes=5)
