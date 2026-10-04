"""App 支持的学科（学科识别 / 出题自由文本解析用的标准集合）与题型白名单。

学科收敛（ADR-0055 §11）：权威学科枚举 = 数学 / 语文 / 英语。前端下拉同源收敛；
**存量其他学科冻结**——照常展示与复习，不能再新建。科学 persona 同步删除。

题型白名单（ADR-0055 §12）：``qtype`` 按学科给白名单 + 默认值——「英语默认
出计算题」这类缺陷的根源是四个题型全学科共用。``open`` 不拆：数学应用题与
语文阅读理解是同一形式，内容由学科 persona 分化。
"""

from __future__ import annotations

# App 支持的学科（学科识别、出题自由文本解析的兜底匹配集合）
SUBJECTS: tuple[str, ...] = ("数学", "语文", "英语")

# 题型全集（字符串约定，历史沿用）
QTYPES: tuple[str, ...] = ("choice", "fill", "calc", "open")

# 按学科的白名单（列表首项即该学科**默认题型**）：
# - 数学保留计算题；语文默认字词默写；英语默认选择题（没有计算题）
SUBJECT_QTYPES: dict[str, list[str]] = {
    "数学": ["calc", "choice", "fill", "open"],
    "语文": ["fill", "choice", "open"],
    "英语": ["choice", "fill", "open"],
}

# 年级统一 1-9（小学 6 + 初中 3）；娃娃资料里的 1-6 是「孩子当前年级」，另一字段
GRADE_MIN, GRADE_MAX = 1, 9


def is_supported_subject(subject: str) -> bool:
    """后端校验入口（ADR-0055 §11：开始校验学科）。"""
    return subject in SUBJECTS


def qtypes_for(subject: str) -> list[str]:
    """某学科的题型白名单；未收敛学科（不应新建，防御性兜底）回全集。"""
    return list(SUBJECT_QTYPES.get(subject) or QTYPES)


def default_qtype(subject: str) -> str:
    """某学科的默认题型 = 白名单首项。"""
    return qtypes_for(subject)[0]


__all__ = [
    "SUBJECTS",
    "QTYPES",
    "SUBJECT_QTYPES",
    "GRADE_MIN",
    "GRADE_MAX",
    "is_supported_subject",
    "qtypes_for",
    "default_qtype",
]
