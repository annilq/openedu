"""遗忘曲线调度纯逻辑单测（T05，故事 14/17）。

覆盖：间隔映射（含越界）、阶段推进与毕业、答错/答对后的到期时间计算。
"""
from datetime import UTC, datetime, timedelta

from app.domain.review_scheduler import (
    REVIEW_INTERVALS_DAYS,
    advance_stage,
    due_after_correct,
    due_after_wrong,
    next_interval_days,
)

NOW = datetime(2026, 8, 20, 12, 0, tzinfo=UTC)


def test_intervals_follow_forgetting_curve():
    assert REVIEW_INTERVALS_DAYS == (1, 2, 4, 7, 15)


def test_next_interval_days_maps_stage_to_interval():
    for stage, days in enumerate(REVIEW_INTERVALS_DAYS):
        assert next_interval_days(stage) == days


def test_next_interval_days_clamps_out_of_range():
    assert next_interval_days(-1) == 1  # 负数按首档
    assert next_interval_days(99) == 15  # 越界按末档


def test_advance_stage_progresses_and_graduates():
    # 0→1→2→3→4 逐步推进
    stage = 0
    for expected in (1, 2, 3, 4):
        assert advance_stage(stage) == expected
        stage = expected
    # 末位（15 天档）再答对 -> 毕业
    assert advance_stage(4) is None


def test_due_after_wrong_resets_to_one_day():
    assert due_after_wrong(NOW) == NOW + timedelta(days=1)


def test_due_after_correct_uses_new_stage_interval():
    # 答对推进到 stage 2 -> 间隔 4 天
    assert due_after_correct(NOW, 2) == NOW + timedelta(days=4)
