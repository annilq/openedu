"""工具 ``delete_questions``：批量硬删题库题（仅教师，ADR-0097）。

与 REST ``DELETE /questions`` 同一下游（``repository.delete_bank_questions``）：
级联清理引用它的数据（任务里的题目副本、作答记录、错题；任务因此变空则连
任务一并删）。归属校验在 repository（owner 隔离）。

**AI 执行删除的边界**：必须先调 ``list_bank_questions`` 让用户看到要删的题、
且用户消息里明确点名（「删掉第 1、3 道」对应 id）才可调用——两步模式，
删除不可逆，不凭模型一句话就删。越权 id 被 owner 过滤，静默忽略。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.shared.tool_support import ToolArgumentError, caller_role, resolve_teacher
from app.features.questions.repository import delete_bank_questions

NAME = "delete_questions"
DESCRIPTION = (
    "批量删除题库里的题目（仅教师，不可逆）。被任务引用的题会连任务里的副本、"
    "作答记录、错题一起清理；任务因此失去全部题目则连任务删除。"
    "调用前必须已向用户展示过要删除的题目并得到明确确认。"
)

_MAX_BATCH = 50


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    if caller_role(ctx) == "student":
        raise ToolArgumentError("删除题库仅教师可用。")

    teacher = resolve_teacher(session=session, ctx=ctx)

    raw_ids = args.get("question_ids")
    if not isinstance(raw_ids, list) or not raw_ids:
        raise ToolArgumentError(
            "question_ids 必须是非空 id 数组（先调 list_bank_questions 拿到题目 id）。"
        )
    if len(raw_ids) > _MAX_BATCH:
        raise ToolArgumentError(f"一次最多删除 {_MAX_BATCH} 道题，收到 {len(raw_ids)} 个 id。")

    from uuid import UUID

    ids: list[UUID] = []
    for raw in raw_ids:
        try:
            ids.append(UUID(str(raw)))
        except (ValueError, TypeError, AttributeError) as exc:
            raise ToolArgumentError(f"question_ids 含非法 uuid：{raw!r}") from exc

    result = delete_bank_questions(
        session=session, teacher_id=teacher.id, question_ids=ids
    )
    return {
        "deleted": [str(i) for i in result.get("deleted", [])],
        "deleted_tasks": [str(i) for i in result.get("deleted_tasks", [])],
        "skipped_forbidden": [str(i) for i in result.get("skipped_forbidden", [])],
    }


SPEC = ToolSpec(
    name=NAME,
    label="删除题目",
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {
            "question_ids": {
                "type": "array",
                "items": {"type": "string"},
                "description": "要删除的题目 id 列表（来自 list_bank_questions 的返回）。",
            },
        },
        "required": ["question_ids"],
    },
    handler=handler,
)
