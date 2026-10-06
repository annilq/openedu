"""工具 ``list_teacher_tasks``：任务清单查询。

- **教师**：我发布的任务（可按学生 / 状态过滤；未派发的草稿任务走 ``unassigned_items``）；
- **学生**：我今天要做的任务——学生没有「发布任务」概念，也**绝不**能看到
  兄弟姐妹的任务，故在学生端等价于 ``list_today_tasks``（而非教师视角的任务表）。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.subagents.query.tools._shared import (
    LOCATOR_PROPS,
    NO_FILTER,
    ToolArgumentError,
    caller_role,
    dump,
    envelope,
    optional_str,
    project_for_role,
    resolve_students,
    resolve_teacher,
    student_block,
)
from app.features.tasks import service as tasks_service

NAME = "list_teacher_tasks"
DESCRIPTION = (
    "查询任务清单。教师：我发布的任务（可用 status 过滤 draft/assigned/done/all）。"
    "学生：我今天要做的任务。用于「我有哪些任务」「作业做完了吗」这类问题。"
)

TASK_STATUSES = ("draft", "assigned", "done")


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    # 缺席归一：strict 模式会替模型补 ""，模型也可能自发填 all/none（见 _shared 顶部说明）。
    status = optional_str(args.get("status"))
    if status is not None and status not in TASK_STATUSES:
        raise ToolArgumentError(
            f"status 只能是 {[NO_FILTER, *TASK_STATUSES]} 之一，收到：{status!r}"
        )
    student_id = optional_str(args.get("student_id"))
    student_name = optional_str(args.get("student_name"))
    # 是否显式指定了目标学生：决定「未指派任务」是否随响应返回。
    explicit_target = bool(student_id or student_name)

    students = resolve_students(
        session=session, ctx=ctx, student_id=student_id, student_name=student_name
    )

    if caller_role(ctx) == "student":
        blocks = [
            student_block(
                c, dump(tasks_service.list_today_tasks(session=session, student_id=c.id))
            )
            for c in students
        ]
        return project_for_role(envelope(blocks), ctx.role)

    teacher = resolve_teacher(session=session, ctx=ctx)
    rows = tasks_service.list_teacher_tasks(
        session=session, teacher_id=teacher.id, status=status
    )
    by_student: dict[Any, list[Any]] = {}
    for row in rows:
        by_student.setdefault(row.student_id, []).append(dump(row))

    blocks = [student_block(c, by_student.pop(c.id, [])) for c in students]
    # 精确指定目标时不返回任何其他学生/未派发的任务（防越权外溢）。
    unassigned = (
        [] if explicit_target else [item for items in by_student.values() for item in items]
    )
    return project_for_role(envelope(blocks, unassigned=unassigned), ctx.role)


SPEC = ToolSpec(
    name=NAME,
    label="查询任务列表",
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {
            **LOCATOR_PROPS,
            "status": {
                "type": "string",
                # enum 必须含 NO_FILTER：strict 模式下参数被强制必填，枚举里没有「全部」
                # 取值时模型无合法值可填，只能填 "" → 被拒 → 陷入重试（ADR-0040）。
                "enum": [NO_FILTER, *TASK_STATUSES],
                "description": (
                    "任务状态过滤：draft 草稿 / assigned 已派发 / done 已完成 / "
                    "all 全部。不过滤时传 all 或空字符串。"
                ),
            },
        },
        "required": [],
    },
    handler=handler,
)
