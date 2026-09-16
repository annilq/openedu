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
    """末位阶段答对 = 毕业：打 graduated_at 时间戳，**不删行**（ADR-0053 P2）。

    此前是物理删除，代价是「这题错过 5 次、现在掌握了」永久查不到，且 mastery 的
    active_wrong / max_review_stage 会掉档。毕业要的是「退出复习队列」，
    不是「抹掉这行」。
    """
    last = len(REVIEW_INTERVALS_DAYS) - 1
    wq = _make_wq(stage=last)
    db.add(wq)
    db.commit()
    db.refresh(wq)

    out = apply_review_outcome(session=db, wq=wq, correct=True)

    assert out is not None
    assert out.graduated_at is not None
    # 行还在：痕迹留着，家长端「已掌握」分区能翻出来。
    assert db.get(WrongQuestion, wq.id) is not None


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
    # 重置回首档 1 天；SQLite 往返后 due_at 为 naive UTC，统一去 tz 比较
    assert out.due_at.replace(tzinfo=None) <= datetime.now(UTC).replace(tzinfo=None) + timedelta(days=1, minutes=5)
