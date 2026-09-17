"""工具 ``list_wrong_questions``：错题本查询（双端）。

家长视角含答案与解析（供核查）；娃娃端由 ``project_for_role`` 统一剥掉
``answer`` / ``explanation``（ADR-008 硬门槛）——本工具**恒以全量查询**，
不自行判断角色，裁剪只发生在投影层。
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
    optional_int,
    optional_str,
    project_for_role,
    resolve_children,
)
from app.features.tasks import service as tasks_service

NAME = "list_wrong_questions"
DESCRIPTION = (
    "查询错题本。家长可看到每题答案与解析；娃娃端自动隐藏答案。"
    "可用 subject 按学科过滤。用于「最近错了哪些题」「哪块知识老出错」。"
)

MAX_LIMIT = 200


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    # 缺席归一（ADR-0040）：strict 模式会替模型补 ""/0，模型也可能自发填 all/none。
    subject = optional_str(args.get("subject"))
    limit = optional_int(args.get("limit"), name="limit")
    if limit is not None:
        limit = min(limit, MAX_LIMIT)

    children = resolve_children(
        session=session,
        ctx=ctx,
        child_id=args.get("child_id"),
        child_name=args.get("child_name"),
    )

    blocks = []
    for child in children:
        rows = tasks_service.list_wrong_questions(
            session=session, child_id=child.id, include_answer=True
        )
        if subject:
            rows = [r for r in rows if r.subject == subject]
        if limit is not None:
            rows = rows[:limit]
        blocks.append(child_block(child, dump(rows)))

    return project_for_role(envelope(blocks), ctx.role)


SPEC = ToolSpec(
    name=NAME,
    label="查询错题本",
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {
            **LOCATOR_PROPS,
            "subject": {
                "type": "string",
                "description": "学科过滤，如「数学」「语文」；不传或传空字符串＝全部学科。",
            },
            "limit": {
                "type": "integer",
                "description": f"最多返回多少道错题（0 或空＝不限，上限 {MAX_LIMIT}）。",
            },
        },
        "required": [],
    },
    handler=handler,
)
