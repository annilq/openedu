"""工具 ``list_parent_tasks``：任务清单查询。

- **家长**：我发布的任务（可按娃娃 / 状态过滤；未派发的草稿任务走 ``unassigned_items``）；
- **娃娃**：我今天要做的任务——娃娃没有「发布任务」概念，也**绝不**能看到
  兄弟姐妹的任务，故在孩子端等价于 ``list_today_tasks``（而非家长视角的任务表）。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.subagents.query.tools._shared import (
    LOCATOR_PROPS,
    ToolArgumentError,
    caller_role,
    child_block,
    dump,
    envelope,
    project_for_role,
    resolve_children,
    resolve_parent,
)
from app.features.tasks import service as tasks_service

NAME = "list_parent_tasks"
DESCRIPTION = (
    "查询任务清单。家长：我发布的任务（可用 status 过滤 draft/assigned/done）。"
    "娃娃：我今天要做的任务。用于「我有哪些任务」「作业做完了吗」这类问题。"
)

TASK_STATUSES = ("draft", "assigned", "done")


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    status = args.get("status")
    if status is not None and status not in TASK_STATUSES:
        raise ToolArgumentError(
            f"status 只能是 {list(TASK_STATUSES)} 之一，收到：{status!r}"
        )
    child_id = args.get("child_id")
    child_name = args.get("child_name")
    # 是否显式指定了目标娃娃：决定「未指派任务」是否随响应返回。
    explicit_target = bool(child_id) or bool(str(child_name or "").strip())

    children = resolve_children(
        session=session, ctx=ctx, child_id=child_id, child_name=child_name
    )

    if caller_role(ctx) == "child":
        blocks = [
            child_block(
                c, dump(tasks_service.list_today_tasks(session=session, child_id=c.id))
            )
            for c in children
        ]
        return project_for_role(envelope(blocks), ctx.role)

    parent = resolve_parent(session=session, ctx=ctx)
    rows = tasks_service.list_parent_tasks(
        session=session, parent_id=parent.id, status=status
    )
    by_child: dict[Any, list[Any]] = {}
    for row in rows:
        by_child.setdefault(row.child_id, []).append(dump(row))

    blocks = [child_block(c, by_child.pop(c.id, [])) for c in children]
    # 精确指定目标时不返回任何其他娃娃/未派发的任务（防越权外溢）。
    unassigned = (
        [] if explicit_target else [item for items in by_child.values() for item in items]
    )
    return project_for_role(envelope(blocks, unassigned=unassigned), ctx.role)


SPEC = ToolSpec(
    name=NAME,
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {
            **LOCATOR_PROPS,
            "status": {
                "type": "string",
                "enum": list(TASK_STATUSES),
                "description": "任务状态过滤：draft 草稿 / assigned 已派发 / done 已完成。不传＝全部。",
            },
        },
        "required": [],
    },
    handler=handler,
)
