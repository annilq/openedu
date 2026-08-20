"""AI 使用管控规则单测（T10，故事 23/26）。

覆盖：默认放行、学科越界 403、次数上限 429、时长上限 429、
0 = 今日禁用、多条件叠加时的判定顺序、配置校验值域。
"""
from app.domain.quota import (
    REASON_ASK_LIMIT,
    REASON_SUBJECT_SCOPE,
    REASON_TIME_LIMIT,
    check_quota,
    validate_quota_config,
)


def _check(**overrides):
    kwargs = dict(
        subject="数学",
        asks_today=0,
        used_seconds=0,
        ask_limit=None,
        minutes_limit=None,
        allowed_subjects=None,
    )
    kwargs.update(overrides)
    return check_quota(**kwargs)


# —— 放行 ——
def test_no_limits_allows():
    d = _check()
    assert d.allowed is True
    assert d.code is None


def test_within_limits_allows():
    d = _check(ask_limit=5, asks_today=4, minutes_limit=10, used_seconds=599)
    assert d.allowed is True


def test_subject_in_scope_allows():
    d = _check(allowed_subjects=["数学", "语文"])
    assert d.allowed is True


# —— 学科越界（内容范围，403）——
def test_subject_out_of_scope_blocked():
    d = _check(subject="英语", allowed_subjects=["数学", "语文"])
    assert d.allowed is False
    assert d.code == REASON_SUBJECT_SCOPE
    assert "数学" in (d.message or "")


# —— 次数上限（429）——
def test_ask_limit_reached_blocked():
    d = _check(ask_limit=3, asks_today=3)
    assert d.allowed is False
    assert d.code == REASON_ASK_LIMIT


def test_ask_limit_zero_blocks_immediately():
    """0 = 今日禁用：一次也不允许。"""
    d = _check(ask_limit=0, asks_today=0)
    assert d.allowed is False
    assert d.code == REASON_ASK_LIMIT


# —— 时长上限（429）——
def test_time_limit_reached_blocked():
    d = _check(minutes_limit=10, used_seconds=600)
    assert d.allowed is False
    assert d.code == REASON_TIME_LIMIT


def test_time_limit_just_below_allows():
    d = _check(minutes_limit=10, used_seconds=599)
    assert d.allowed is True


def test_time_limit_zero_blocks_immediately():
    d = _check(minutes_limit=0, used_seconds=0)
    assert d.allowed is False
    assert d.code == REASON_TIME_LIMIT


# —— 判定顺序 ——
def test_scope_checked_before_limits():
    """学科越界优先于次数/时长：提示应指向内容范围。"""
    d = _check(
        subject="英语",
        allowed_subjects=["数学"],
        ask_limit=0,
        minutes_limit=0,
    )
    assert d.allowed is False
    assert d.code == REASON_SUBJECT_SCOPE


def test_ask_limit_checked_before_time_limit():
    d = _check(ask_limit=0, minutes_limit=0)
    assert d.code == REASON_ASK_LIMIT


# —— 配置校验 ——
def test_validate_accepts_valid_config():
    assert (
        validate_quota_config(
            daily_ask_limit=10,
            daily_minutes_limit=30,
            allowed_subjects=["数学"],
        )
        is None
    )


def test_validate_rejects_negative_limits():
    msg = validate_quota_config(
        daily_ask_limit=-1, daily_minutes_limit=None, allowed_subjects=None
    )
    assert msg is not None and "负数" in msg
    msg = validate_quota_config(
        daily_ask_limit=None, daily_minutes_limit=-5, allowed_subjects=None
    )
    assert msg is not None and "负数" in msg


def test_validate_rejects_empty_subjects():
    msg = validate_quota_config(
        daily_ask_limit=None, daily_minutes_limit=None, allowed_subjects=[]
    )
    assert msg is not None and "不能为空" in msg


def test_validate_rejects_unknown_subject():
    msg = validate_quota_config(
        daily_ask_limit=None, daily_minutes_limit=None, allowed_subjects=["物理"]
    )
    assert msg is not None and "物理" in msg
