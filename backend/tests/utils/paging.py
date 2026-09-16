"""游标分页信封（ADR-0053）的测试读取助手。

三个列表端点（题库 / 任务 / 错题本）的响应都从裸列表变成了
``{"items": [...], "total": N, "page_size": N, "next_cursor": ...}``。
测试里到处写 ``resp.json()["items"]`` 会把「信封长什么样」重复进每条断言——
改一次形状要动十几个文件。收口到这两个函数后，测试读的是「这批数据是什么」，
形状只在这里记一次。
"""
from __future__ import annotations

from typing import Any


def page_of(resp: Any) -> dict[str, Any]:
    """整个分页信封。"""
    return resp.json()


def page_items(resp: Any) -> list[dict[str, Any]]:
    """信封里的条目列表。"""
    return resp.json()["items"]


def page_total(resp: Any) -> int:
    """信封里的总数（只用于「还有 N 条」类断言，不用于翻页判定）。"""
    return resp.json()["total"]


def page_cursor(resp: Any) -> str | None:
    """下一页游标；``None`` = 已到底。"""
    return resp.json()["next_cursor"]
