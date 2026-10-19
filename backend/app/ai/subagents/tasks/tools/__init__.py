"""tasks（任务学情域）业务 agent 的工具注册表（ADR-0097 / ADR-0098）。

学情侧（``TASKS_TOOLS``）：读工具 7 个（6 个自 query 迁入 + list_students 自
students 域吸收，ADR-0098）+ 写工具 1 个（create_draft，AI 只起草、确认卡发布）。

出题侧（ADR-0098 第二波，自 question 域迁入，本票只搬模块不改装配）：
- ``BANK_TOOLS``：题库三个同步工具（list / delete / archive）；
- ``generation_tools``：出题**流式** tool 的装配工厂（``make_spec``，provider
  装配期闭包注入——工具要 provider，故不在模块级构造）。

question agent（票 03 删除前）与合并后的 tasks agent 共用这两组导出；tasks agent
的合体（``TASKS_TOOLS + BANK_TOOLS + generation_tools``）在票 03 落地。
"""
from __future__ import annotations

from agent_core.tools import ToolSpec

from .archive_questions import SPEC as ARCHIVE_QUESTIONS
from .create_draft import SPEC as CREATE_DRAFT
from .delete_questions import SPEC as DELETE_QUESTIONS
from .generate_questions import make_spec as make_generate_spec
from .get_mastery import SPEC as GET_MASTERY
from .get_progress import SPEC as GET_PROGRESS
from .list_bank_questions import SPEC as LIST_BANK_QUESTIONS
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

# 题库侧（自 question 域迁入）：删除不可逆两步模式 / 归档可逆，均只教师可用。
BANK_TOOLS: list[ToolSpec] = [
    LIST_BANK_QUESTIONS,
    DELETE_QUESTIONS,
    ARCHIVE_QUESTIONS,
]


def generation_tools(*, provider, retriever=None) -> list[ToolSpec]:
    """出题侧装配期构造（出题 tool 需要 provider 闭包）。

    自 question 域迁入（ADR-0098）：流式出题 tool 的 provider/retriever 经闭包
    注入，不落全局状态——装配期（agent 实例化）写一次，运行期只读。
    """
    return [make_generate_spec(provider=provider, retriever=retriever)]


__all__ = ["TASKS_TOOLS", "BANK_TOOLS", "generation_tools"]
