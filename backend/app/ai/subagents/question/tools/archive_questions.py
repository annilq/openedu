"""工具 ``archive_questions``：批量归档 / 恢复题库题（仅教师，ADR-0097）。

与 REST ``POST /questions/archive`` 同一下游（``questions.service.set_bank_questions_archived``，
ADR-0097 写路径下沉：业务工具不得直连 repository，分层不变量 7）。
与删除的分工（ADR-0053 P2）：删除是「彻底不要了」（被任务引用的题删不掉），
归档是「先收起来」——被引用也能归档，且随时能恢复（``archived=false``）。
删除不可逆、归档可逆，故 AI 侧默认引导归档而非删除。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.shared.tool_support import ToolArgumentError, caller_role, resolve_teacher
from app.features.questions import service as questions_service

NAME = "archive_questions"
DESCRIPTION = (
    "批量归档或恢复题库题目（仅教师，可逆）。归档后题目默认不在列表显示，"
    "随时可恢复；被任务引用的题也能归档。用户说「收起来 / 先不管这几道 / 恢复」时用本工具。"
)

_MAX_BATCH = 50


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    if caller_role(ctx) == "student":
        raise ToolArgumentError("归档题库仅教师可用。")

    teacher = resolve_teacher(session=session, ctx=ctx)

    raw_ids = args.get("question_ids")
    if not isinstance(raw_ids, list) or not raw_ids:
        raise ToolArgumentError("question_ids 必须是非空 id 数组。")
    if len(raw_ids) > _MAX_BATCH:
        raise ToolArgumentError(f"一次最多操作 {_MAX_BATCH} 道题，收到 {len(raw_ids)} 个 id。")

    # strict 模式缺席编码：布尔用 false，语义上 false = 恢复（见 schema description）。
    archived = bool(args.get("archived"))

    from uuid import UUID

    ids: list[UUID] = []
    for raw in raw_ids:
        try:
            ids.append(UUID(str(raw)))
        except (ValueError, TypeError, AttributeError) as exc:
            raise ToolArgumentError(f"question_ids 含非法 uuid：{raw!r}") from exc

    result = questions_service.set_bank_questions_archived(
        session=session, teacher_id=teacher.id, question_ids=ids, archived=archived
    )
    return {
        "archived": archived,
        "updated": [str(i) for i in result.get("updated", [])],
        "skipped_forbidden": [str(i) for i in result.get("skipped_forbidden", [])],
    }


SPEC = ToolSpec(
    name=NAME,
    label="归档题目",
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {
            "question_ids": {
                "type": "array",
                "items": {"type": "string"},
                "description": "要归档 / 恢复的题目 id 列表（来自 list_bank_questions 的返回）。",
            },
            "archived": {
                "type": "boolean",
                "description": "true＝归档（收起来）；false＝恢复。",
            },
        },
        "required": ["question_ids", "archived"],
    },
    handler=handler,
)
