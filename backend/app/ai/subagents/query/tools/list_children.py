"""工具 ``list_children``：列出当前账号可查询的娃娃。

家长＝名下全部孩子；娃娃＝自己。用于「不确定要查哪个娃娃」时的前置定位
（模型可先调本工具拿到 ``child_id``，再带 id 查明细）。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.subagents.query.tools._shared import (
    child_meta,
    envelope,
    project_for_role,
    resolve_children,
)

NAME = "list_children"
DESCRIPTION = (
    "列出当前账号可查询的娃娃（家长＝名下全部孩子；娃娃＝自己）。"
    "当你不确定要查哪一个娃娃、或需要娃娃的 id 时，先调用本工具。"
)


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    children = resolve_children(session=session, ctx=ctx)
    blocks = [{**child_meta(c), "items": [], "meta": {}} for c in children]
    return project_for_role(envelope(blocks), ctx.role)


SPEC = ToolSpec(
    name=NAME,
    description=DESCRIPTION,
    schema={"type": "object", "properties": {}, "required": []},
    handler=handler,
)
