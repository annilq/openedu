"""遗忘曲线复习调度（T05，故事 14/17）。

纯领域逻辑：给定错题当前阶段，计算下次复习间隔/推进/毕业。
阶段 0..4 对应间隔 1/2/4/7/15 天；末位阶段复习答对即视为掌握，打 graduated_at
时间戳退出复习队列（ADR-0053 P2 起不再物理删除）。
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


def graduate(wq: WrongQuestion, now: datetime) -> WrongQuestion:
    """末位阶段答对 → 毕业（已掌握）：打时间戳而非删除（ADR-0053 P2）。

    物理删除会让「这题错过 5 次、现在掌握了」永久查不到，也会让 ``mastery`` 的
    ``active_wrong`` / ``max_review_stage`` 掉档。毕业仍要让它退出复习队列——
    只是退出的方式是「打时间戳 + 列表默认过滤」，不是「抹掉这行」。
    """
    wq.graduated_at = now
    # due_at 留着：重新加入复习时按首档重算，这里不动，避免毕业动作丢掉调度信息。
    return wq


def apply_review_outcome(
    *, session: Session, wq: WrongQuestion, correct: bool
) -> WrongQuestion:
    """复习/归集作答后的遗忘曲线状态转移（单一事实源）。

    复习作答（``mark_review_result``）与练习答错归集（``upsert_wrong_question``
    的 existing 分支）共用同一状态机，故抽到 domain 层避免两处逐字复制。

    - 答对：推进阶段（1→2→4→7→15 天）；末位阶段答对视为掌握，**打 graduated_at
      时间戳**（ADR-0053 P2 起不再删除实体，仍返回该实体）。
    - 答错：重置为首档 1 天（故事 17），wrong_count +1。若这条错题此前已毕业
      （重新加入复习后又答错），一并清掉毕业时间戳——它重新变成「未掌握」。
    内部自行 commit + refresh；调用方传入已加载的实体，避免重复查询。
    """
    now = datetime.now(UTC)
    if correct:
        new_stage = advance_stage(wq.review_stage)
        if new_stage is None:
            session.add(graduate(wq, now))
            session.commit()
            session.refresh(wq)
            return wq
        wq.review_stage = new_stage
        wq.due_at = due_after_correct(now, new_stage)
    else:
        wq.review_stage = 0
        wq.last_wrong_at = now
        wq.due_at = due_after_wrong(now)
        wq.wrong_count += 1
        if wq.graduated_at is not None:
            wq.graduated_at = None
    session.add(wq)
    session.commit()
    session.refresh(wq)
    return wq
