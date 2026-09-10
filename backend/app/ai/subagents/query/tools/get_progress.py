"""工具 ``get_progress``：学习进度概况（累计作答 / 正确率 / 打卡）。

进度是单条聚合结果，但沿用统一信封（放进 ``items`` 的单元素列表），
使全部查询工具同构——契约测试与渲染 hook 无需为特例分支。
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

NAME = "get_progress"
DESCRIPTION = (
    "查询学习进度概况：累计作答数、答对数、正确率、连续打卡天数、累计打卡天数。"
    "用于「最近学得怎么样」「坚持打卡多少天了」。"
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
        progress = tasks_service.child_progress(session=session, child_id=child.id)
        blocks.append(child_block(child, [dump(progress)]))

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
