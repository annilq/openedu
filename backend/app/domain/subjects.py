"""App 支持的学科（学科识别 / 出题自由文本解析用的标准集合）。

从原 ``domain.quota`` 迁出不依赖配额（SUBJECTS 是学科枚举，被 subject 识别与出题
解析共用，与每日上限无关）。
"""
from __future__ import annotations

# App 支持的学科（学科识别、出题自由文本解析的兜底匹配集合）
SUBJECTS: tuple[str, ...] = ("数学", "语文", "英语")

__all__ = ["SUBJECTS"]
