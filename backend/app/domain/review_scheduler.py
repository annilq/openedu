"""遗忘曲线复习调度（T05，故事 14/17）。

纯领域逻辑：给定错题当前阶段，计算下次复习间隔/推进/毕业。
阶段 0..4 对应间隔 1/2/4/7/15 天；末位阶段复习答对即视为掌握，从错题集移除。
"""
from datetime import datetime, timedelta

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
