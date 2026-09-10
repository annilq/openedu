"""工具 ``list_today_tasks``：今日任务查询（双端）。

家长：指定娃娃或名下全部娃娃今天要做的任务；娃娃：自己的今日任务。
与 ``list_parent_tasks`` 的区别是**只关心今天**，用于「今天有什么作业」这类问句。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.subagents.query.tools._shared import (
    LOCATOR_PROPS,
    child_block,
    dump,
    envelope,
    project_for_role,
    resolve_children,
)
from app.features.tasks import service as tasks_service

NAME = "list_today_tasks"
DESCRIPTION = (
    "查询今天要做的任务（家长：指定或名下全部娃娃；娃娃：自己）。"
    "用于「今天有什么作业」「今天的任务做完了吗」。"
)


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    children = resolve_children(
        session=session,
        ctx=ctx,
        child_id=args.get("child_id"),
        child_name=args.get("child_name"),
    )
    blocks = [
        child_block(
            c, dump(tasks_service.list_today_tasks(session=session, child_id=c.id))
        )
        for c in children
    ]
    return project_for_role(envelope(blocks), ctx.role)


SPEC = ToolSpec(
    name=NAME,
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {**LOCATOR_PROPS},
        "required": [],
    },
    handler=handler,
)
