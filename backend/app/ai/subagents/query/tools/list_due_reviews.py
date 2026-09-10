"""工具 ``list_due_reviews``：待复习队列查询（遗忘曲线到期项）。

面向「今天该复习什么」；复习项本身不含答案（``ReviewItemResp`` 无 answer 字段），
但仍统一过 ``project_for_role``，保持「裁剪只在一处」的口径。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.subagents.query.tools._shared import (
    LOCATOR_PROPS,
    ToolArgumentError,
    child_block,
    dump,
    envelope,
    project_for_role,
    resolve_children,
)
from app.features.review import service as review_service

NAME = "list_due_reviews"
DESCRIPTION = (
    "查询今天到期的待复习错题（按遗忘曲线排期）。"
    "用于「今天要复习什么」「还有多少题要复习」。"
)


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    limit = args.get("limit")
    if limit is not None:
        try:
            limit = int(limit)
        except (TypeError, ValueError) as exc:
            raise ToolArgumentError(f"limit 必须是整数，收到：{limit!r}") from exc
        if limit <= 0:
            raise ToolArgumentError("limit 必须大于 0。")

    children = resolve_children(
        session=session,
        ctx=ctx,
        child_id=args.get("child_id"),
        child_name=args.get("child_name"),
    )
    blocks = []
    for child in children:
        rows = review_service.list_due_reviews(session=session, child_id=child.id)
        if limit is not None:
            rows = rows[:limit]
        blocks.append(child_block(child, dump(rows)))

    return project_for_role(envelope(blocks), ctx.role)


SPEC = ToolSpec(
    name=NAME,
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {
            **LOCATOR_PROPS,
            "limit": {
                "type": "integer",
                "description": "最多返回多少道待复习题（不传＝全部）。",
            },
        },
        "required": [],
    },
    handler=handler,
)
