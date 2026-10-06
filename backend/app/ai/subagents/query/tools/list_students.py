"""工具 ``list_students``：列出当前账号可查询的学生。

教师＝名下全部学生；学生＝自己。用于「不确定要查哪个学生」时的前置定位
（模型可先调本工具拿到 ``student_id``，再带 id 查明细）。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.subagents.query.tools._shared import (
    envelope,
    project_for_role,
    resolve_students,
    student_meta,
)

NAME = "list_students"
DESCRIPTION = (
    "列出当前账号可查询的学生（教师＝名下全部学生；学生＝自己）。"
    "用于用户想了解有哪些学生、或需要学生 id 消歧时；"
    "只想查某个学生的明细，请直接用其他工具的 student_name，不必先调用本工具。"
)


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    students = resolve_students(session=session, ctx=ctx)
    blocks = [{**student_meta(c), "items": [], "meta": {}} for c in students]
    return project_for_role(envelope(blocks), ctx.role)


SPEC = ToolSpec(
    name=NAME,
    label="查询学生列表",
    description=DESCRIPTION,
    schema={"type": "object", "properties": {}, "required": []},
    handler=handler,
)
