"""工具 ``create_draft``：从题库选题组建**草稿**任务（仅教师，ADR-0097）。

写操作的边界（ADR-0097 §2.3）：AI 只**起草**——建出来的是 draft 态任务，
不派发。确认与派发由用户在会话内的确认卡上点「确认发布」完成（前端直走
现有 REST ``POST /tasks/{id}/confirm`` + ``/assign``），发布决定权与任务页
按钮同权。产品立场（ADR-0087）：发布任务要由用户亲自定题并确认。

选题：``question_ids`` 显式给出时用；缺省按 subject/grade/knowledge_point
从题库取最近 N 道（复用 questions service 的查询，不另造选題逻辑）。
目标学生**必填**（student_id / student_name 二选一）——未指名就建任务是
误派发的高危形态，宁可让模型转问。
"""
from __future__ import annotations

from typing import Any
from uuid import UUID

from agent_core.protocol import data_event
from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.shared.tool_support import (
    ToolArgumentError,
    caller_role,
    envelope,
    optional_int,
    optional_str,
    project_for_role,
    resolve_students,
    resolve_teacher,
    student_block,
)
from app.features.questions import service as questions_service
from app.features.tasks import service as tasks_service

NAME = "create_draft"
DESCRIPTION = (
    "从题库选题组建草稿任务（仅教师，不派发）。创建后用户会在确认卡上点「确认发布」"
    "才真正派发。必须指定目标学生；可显式给出题目 id，或按科目/年级/知识点自动选取。"
)

DRAFT_CARD_KIND = "task_draft_card"
_MAX_PICK = 10


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    if caller_role(ctx) == "student":
        raise ToolArgumentError("创建任务仅教师可用。")

    teacher = resolve_teacher(session=session, ctx=ctx)

    # 目标学生必填：未指名的起草是误派发高危形态，回灌让模型转问。
    student_id = optional_str(args.get("student_id"))
    student_name = optional_str(args.get("student_name"))
    if not student_id and not student_name:
        raise ToolArgumentError(
            "必须指定目标学生（student_id 或 student_name 二选一）——"
            "不知道派给谁时先问用户，不要擅自建任务。"
        )
    students = resolve_students(
        session=session,
        ctx=ctx,
        student_id=student_id,
        student_name=student_name,
    )
    if len(students) != 1:
        raise ToolArgumentError(
            f"目标学生不明确：命中 {len(students)} 人。草稿任务只派给一个学生，"
            "请让用户指明（同名时用 student_id）。"
        )
    target = students[0]

    subject = optional_str(args.get("subject"))
    count = optional_int(args.get("count"), name="count")
    count = min(count or 3, _MAX_PICK)

    # 题目 id：显式给出 → 用；缺省 → 按科目/年级/知识点从题库取最近 N 道。
    raw_ids = args.get("question_ids")
    question_ids: list[UUID] = []
    if isinstance(raw_ids, list) and raw_ids:
        for raw in raw_ids:
            try:
                question_ids.append(UUID(str(raw)))
            except (ValueError, TypeError, AttributeError) as exc:
                raise ToolArgumentError(f"question_ids 含非法 uuid：{raw!r}") from exc
    else:
        picked = questions_service.list_bank_questions(
            session=session,
            teacher_id=teacher.id,
            subject=subject,
            limit=count,
        )
        question_ids = [UUID(str(q["id"])) for q in picked]
        if not question_ids:
            raise ToolArgumentError(
                "题库里没有符合条件的题目。请先出题（generate_questions）或换过滤条件。"
            )

    title = optional_str(args.get("title")) or _default_title(subject, target.display_name, len(question_ids))
    task = tasks_service.create_from_bank(
        session=session,
        teacher_id=teacher.id,
        title=title,
        student_id=target.id,
        question_ids=question_ids,
    )
    payload = {
        "task_id": str(task.id),
        "title": task.title,
        "subject": subject or "",
        "grade": int(args.get("grade") or 0),
        "question_count": len(question_ids),
        "students": [target.display_name or ""],
    }
    # 回灌模型的 content：草稿摘要（task_id + 题数 + 目标），话术据此生成。
    return project_for_role(
        envelope(
            [
                student_block(
                    target,
                    [payload],
                    meta={"task_id": payload["task_id"], "draft": True},
                )
            ],
        ),
        ctx.role,
    )


def _default_title(subject: str | None, student_name: str, count: int) -> str:
    who = student_name or "学生"
    what = f"{subject}练习" if subject else "练习"
    return f"{who}的{what}（{count} 题）"


def draft_card(payload: dict[str, Any]) -> Any:
    """草稿确认卡的 DATA 帧（ADR-0097 §2.3 / ADR-0042）。

    ``data.type = task_draft_card``，前端渲染「确认发布 / 取消」按钮——按钮直走
    REST，不新造 AI 确认机制。
    """
    return data_event(payload, extra={"type": DRAFT_CARD_KIND})


SPEC = ToolSpec(
    name=NAME,
    label="组建草稿任务",
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {
            "student_id": {
                "type": "string",
                "description": "目标学生账号 ID（uuid）；与 student_name 二选一，必填。",
            },
            "student_name": {
                "type": "string",
                "description": "目标学生昵称（模糊匹配）；与 student_id 二选一，必填。",
            },
            "question_ids": {
                "type": "array",
                "items": {"type": "string"},
                "description": "显式选题（题库题 id 列表）；不传则按科目/年级自动选取。",
            },
            "subject": {
                "type": "string",
                "description": "科目（自动选题时过滤）；如 数学 / 语文 / 英语。",
            },
            "grade": {
                "type": "integer",
                "description": "年级（仅进卡片展示与默认标题）；0 或空＝不限。",
            },
            "count": {
                "type": "integer",
                "description": f"自动选题数量（1-{_MAX_PICK}）；0 或空＝3。",
            },
            "title": {
                "type": "string",
                "description": "任务标题；空＝按「学生+科目+题数」自动生成。",
            },
        },
        "required": [],
    },
    handler=handler,
)
