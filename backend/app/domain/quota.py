"""AI 使用管控规则（T10 / 故事 23/26，PRD 三期 State-driven EARS）。

家长可按娃娃配置三类管控，系统在每次答疑前强制校验：
1. 每日提问条数上限（daily_ask_limit，None 时回退全局 TUTOR_DAILY_LIMIT）
2. 每日累计使用时长上限（daily_minutes_limit，服务端按每次答疑耗时累计秒数）
3. 内容范围（allowed_subjects 允许学科白名单，None 表示全部）

规则为纯函数，便于单测覆盖；调用方（routes/tutor.py）负责取数与落库。

值域约定：上限为 0 表示「今日禁用 AI 答疑」，None 表示不启用该项管控。
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.db.models import TutorQuota

# App 支持的学科（家长配置范围时的合法选项）
SUBJECTS: tuple[str, ...] = ("数学", "语文", "英语")

# 拦截原因码：ask_limit/time_limit 对应 429，subject_scope 对应 403
REASON_ASK_LIMIT = "ask_limit"
REASON_TIME_LIMIT = "time_limit"
REASON_SUBJECT_SCOPE = "subject_scope"


@dataclass(frozen=True)
class QuotaDecision:
    allowed: bool
    code: str | None = None
    message: str | None = None


@dataclass(frozen=True)
class QuotaLimits:
    """某娃娃生效后的管控限额（合并全局默认与每娃覆盖后）。"""

    ask_limit: int | None
    minutes_limit: int | None
    allowed_subjects: list[str] | None


def resolve_quota_limits(
    quota: "TutorQuota | None",
    *,
    default_ask_limit: int | None = None,
) -> QuotaLimits:
    """把（可能 None 的）TutorQuota 行合并为生效限额。

    未配置某项时回退 ``default_ask_limit``（通常传全局 ``settings.TUTOR_DAILY_LIMIT``）。
    消除各路由里重复的「全局默认 + 每娃 quota 合并」逻辑（ADR-0027：共享逻辑进 domain）。
    """
    ask_limit = default_ask_limit
    minutes_limit = None
    allowed_subjects = None
    if quota is not None:
        if quota.daily_ask_limit is not None:
            ask_limit = quota.daily_ask_limit
        minutes_limit = quota.daily_minutes_limit
        allowed_subjects = quota.allowed_subjects
    return QuotaLimits(ask_limit, minutes_limit, allowed_subjects)


def check_quota(
    *,
    subject: str,
    asks_today: int,
    used_seconds: int,
    ask_limit: int | None,
    minutes_limit: int | None,
    allowed_subjects: list[str] | None,
) -> QuotaDecision:
    """答疑前管控校验：学科范围 → 次数上限 → 时长上限。

    - 学科越界：请求与本娃学习无关（按家长设定的范围），403 拒绝并提示。
    - 次数/时长达上限：超额使用，429 拒绝并提示（PRD State-driven EARS）。
    """
    if allowed_subjects is not None and subject not in allowed_subjects:
        return QuotaDecision(
            allowed=False,
            code=REASON_SUBJECT_SCOPE,
            message=(
                f"家长仅允许提问 {'、'.join(allowed_subjects)} 相关问题，"
                "先完成这些学科的学习吧～"
            ),
        )
    if ask_limit is not None and asks_today >= ask_limit:
        return QuotaDecision(
            allowed=False,
            code=REASON_ASK_LIMIT,
            message=f"今日 AI 答疑次数已达上限（{ask_limit} 次），明天再来哦～",
        )
    if minutes_limit is not None and used_seconds >= minutes_limit * 60:
        return QuotaDecision(
            allowed=False,
            code=REASON_TIME_LIMIT,
            message=(
                f"今日 AI 使用时长已达上限（{minutes_limit} 分钟），"
                "休息一下眼睛吧～"
            ),
        )
    return QuotaDecision(allowed=True)


def validate_quota_config(
    *,
    daily_ask_limit: int | None,
    daily_minutes_limit: int | None,
    allowed_subjects: list[str] | None,
) -> str | None:
    """家长配置校验：返回错误信息（None 表示合法）。

    - 上限须为非负整数（0 = 今日禁用）；负数无意义。
    - 学科范围须为非空且都在 SUBJECTS 内。
    """
    if daily_ask_limit is not None and daily_ask_limit < 0:
        return "每日提问上限不能为负数"
    if daily_minutes_limit is not None and daily_minutes_limit < 0:
        return "每日时长上限不能为负数"
    if allowed_subjects is not None:
        if not allowed_subjects:
            return "允许学科不能为空列表（不限制请传 null）"
        unknown = [s for s in allowed_subjects if s not in SUBJECTS]
        if unknown:
            return f"不支持的学科：{'、'.join(unknown)}（可选：{'、'.join(SUBJECTS)}）"
    return None


__all__ = [
    "SUBJECTS",
    "QuotaDecision",
    "QuotaLimits",
    "check_quota",
    "resolve_quota_limits",
    "validate_quota_config",
    "REASON_ASK_LIMIT",
    "REASON_TIME_LIMIT",
    "REASON_SUBJECT_SCOPE",
]
