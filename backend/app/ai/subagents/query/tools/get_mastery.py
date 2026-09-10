"""工具 ``get_mastery``：知识点掌握度看板。

每个知识点一条（得分 / 等级 / 错题数 / 复习阶段）；娃娃端可查自己的看板
（无答案泄漏风险，与 ``/tasks/children/{id}/mastery`` 放开给娃娃端一致）。
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
from app.features.mastery import service as mastery_service

NAME = "get_mastery"
DESCRIPTION = (
    "查询知识点掌握度看板：每个知识点的掌握分数、等级（已掌握/薄弱等）、"
    "错题数、复习阶段。用于「哪些知识点掌握得好、哪些还薄弱」。"
)


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    children = resolve_children(
        session=session,
        ctx=ctx,
        child_id=args.get("child_id"),
        child_name=args.get("child_name"),
    )
    blocks = []
    for child in children:
        board = mastery_service.build_mastery(session=session, child_id=child.id)
        blocks.append(
            child_block(
                child,
                dump(board.items),
                meta={
                    "total_knowledge_points": board.total_knowledge_points,
                    "mastered_count": board.mastered_count,
                },
            )
        )

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
