"""tasks（任务学情域）业务 agent 的工具注册表（ADR-0097 / ADR-0098）。

读工具 7 个：6 个自 query 子代理迁入（学情查询）+ list_students（自 students 域
吸收，ADR-0098）；写工具 1 个（create_draft，AI 只起草、确认卡发布）。
全部为同步工具——本域无流式执行体（出题流式 tool 在 ADR-0098 第二波并入）。
"""
from __future__ import annotations

from agent_core.tools import ToolSpec

from .create_draft import SPEC as CREATE_DRAFT
from .get_mastery import SPEC as GET_MASTERY
from .get_progress import SPEC as GET_PROGRESS
from .list_due_reviews import SPEC as LIST_DUE_REVIEWS
from .list_students import SPEC as LIST_STUDENTS
from .list_teacher_tasks import SPEC as LIST_TEACHER_TASKS
from .list_today_tasks import SPEC as LIST_TODAY_TASKS
from .list_wrong_questions import SPEC as LIST_WRONG_QUESTIONS

TASKS_TOOLS: list[ToolSpec] = [
    LIST_TEACHER_TASKS,
    LIST_TODAY_TASKS,
    LIST_WRONG_QUESTIONS,
    GET_PROGRESS,
    LIST_DUE_REVIEWS,
    GET_MASTERY,
    LIST_STUDENTS,
    CREATE_DRAFT,
]

__all__ = ["TASKS_TOOLS"]
