"""Shared ORM helpers used by table definitions in this package."""

from datetime import UTC, date, datetime, timedelta


def get_datetime_utc() -> datetime:
    return datetime.now(UTC)


def get_review_due_utc() -> datetime:
    """错题首次归集时：1 天后到期复习（遗忘曲线首档间隔）。"""
    return datetime.now(UTC) + timedelta(days=1)


def get_usage_date_utc() -> date:
    """当日用量行的日期口径：统一 UTC（与 created_at 存储时区一致）。"""
    return datetime.now(UTC).date()
