"""``query`` 工具注册表：把 7 个只读工具汇总为 runtime 消费的 ``ToolSpec`` 列表。

顺序即随请求下发给模型的顺序；把「定位类」工具（``list_children``）放最前，
与「不确定查谁就先列娃娃」的 SOP 一致。
"""
from __future__ import annotations

from agent_core.tools import ToolSpec

from .get_mastery import SPEC as GET_MASTERY
from .get_progress import SPEC as GET_PROGRESS
from .list_children import SPEC as LIST_CHILDREN
from .list_due_reviews import SPEC as LIST_DUE_REVIEWS
from .list_parent_tasks import SPEC as LIST_PARENT_TASKS
from .list_today_tasks import SPEC as LIST_TODAY_TASKS
from .list_wrong_questions import SPEC as LIST_WRONG_QUESTIONS

QUERY_TOOLS: list[ToolSpec] = [
    LIST_CHILDREN,
    LIST_PARENT_TASKS,
    LIST_TODAY_TASKS,
    LIST_WRONG_QUESTIONS,
    LIST_DUE_REVIEWS,
    GET_PROGRESS,
    GET_MASTERY,
]

__all__ = ["QUERY_TOOLS"]
