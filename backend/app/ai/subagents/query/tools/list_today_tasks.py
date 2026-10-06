"""工具 ``list_today_tasks``：今日任务查询（双端）。

教师：指定学生或名下全部学生今天要做的任务；学生：自己的今日任务。
与 ``list_teacher_tasks`` 的区别是**只关心今天**，用于「今天有什么作业」这类问句。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.subagents.query.tools._shared import (
    LOCATOR_PROPS,
    dump,
    envelope,
    project_for_role,
    resolve_students,
    student_block,
)
from app.features.tasks import service as tasks_service

NAME = "list_today_tasks"
DESCRIPTION = (
    "查询今天要做的任务（教师：指定或名下全部学生；学生：自己）。"
    "用于「今天有什么作业」「今天的任务做完了吗」。"
)


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    students = resolve_students(
        session=session,
        ctx=ctx,
        student_id=args.get("student_id"),
        student_name=args.get("student_name"),
    )
    blocks = [
        student_block(
            c, dump(tasks_service.list_today_tasks(session=session, student_id=c.id))
        )
        for c in students
    ]
    return project_for_role(envelope(blocks), ctx.role)


SPEC = ToolSpec(
    name=NAME,
    label="查询今日任务",
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {**LOCATOR_PROPS},
        "required": [],
    },
    handler=handler,
)
