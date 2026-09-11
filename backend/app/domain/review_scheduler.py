"""遗忘曲线复习调度（T05，故事 14/17）。

纯领域逻辑：给定错题当前阶段，计算下次复习间隔/推进/毕业。
阶段 0..4 对应间隔 1/2/4/7/15 天；末位阶段复习答对即视为掌握，从错题集移除。
"""
from datetime import UTC, datetime, timedelta

from sqlmodel import Session

from app.db.models import WrongQuestion

REVIEW_INTERVALS_DAYS: tuple[int, ...] = (1, 2, 4, 7, 15)


def next_interval_days(stage: int) -> int:
    """当前阶段对应的复习间隔天数（越界取末位档）。"""
    idx = min(max(stage, 0), len(REVIEW_INTERVALS_DAYS) - 1)
    return REVIEW_INTERVALS_DAYS[idx]


def advance_stage(stage: int) -> int | None:
    """复习答对后推进到下一阶段；已处于末位阶段返回 None（毕业/掌握）。"""
    if stage >= len(REVIEW_INTERVALS_DAYS) - 1:
        return None
    return stage + 1


def due_after_wrong(now: datetime) -> datetime:
    """答错（含首次归集/重复错/复习答错）后：重置为首档 1 天（故事 17）。"""
    return now + timedelta(days=REVIEW_INTERVALS_DAYS[0])


def due_after_correct(now: datetime, new_stage: int) -> datetime:
    """复习答对推进到 new_stage 后，下一次到期时间。"""
    return now + timedelta(days=next_interval_days(new_stage))


def apply_review_outcome(
    *, session: Session, wq: WrongQuestion, correct: bool
) -> WrongQuestion | None:
    """复习/归集作答后的遗忘曲线状态转移（单一事实源）。

    复习作答（``mark_review_result``）与练习答错归集（``upsert_wrong_question``
    的 existing 分支）共用同一状态机，故抽到 domain 层避免两处逐字复制。

    - 答对：推进阶段（1→2→4→7→15 天）；末位阶段答对视为掌握，删除实体并返回 None。
    - 答错：重置为首档 1 天（故事 17），wrong_count +1。
    内部自行 commit + refresh；调用方传入已加载的实体，避免重复查询。
    """
    now = datetime.now(UTC)
    if correct:
        new_stage = advance_stage(wq.review_stage)
        if new_stage is None:
            session.delete(wq)
            session.commit()
            return None
        wq.review_stage = new_stage
        wq.due_at = due_after_correct(now, new_stage)
    else:
        wq.review_stage = 0
        wq.last_wrong_at = now
        wq.due_at = due_after_wrong(now)
        wq.wrong_count += 1
    session.add(wq)
    session.commit()
    session.refresh(wq)
    return wq
