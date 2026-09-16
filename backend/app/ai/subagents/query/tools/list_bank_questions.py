"""工具 ``list_bank_questions``：题库题目查询（仅家长）。

题库归属家长（``Question.parent_id`` owner 隔离），与任何娃娃无外键关联——
故本工具**不接受** child 定位参数、不按娃娃分组、娃娃端直接返回「仅家长可用」。
复用 query SubAgent 的统一出参信封（``children`` / ``unassigned_items`` /
``total_*``），单块以合成 ``{id:"bank", name:"题库"}`` 承载（契约测试断言每块
含 ``id/name/grade/items/meta``）。参考 ``list_parent_tasks`` 的实现形态。
"""
from __future__ import annotations

from typing import Any

from agent_core.subagent import SubAgentContext
from agent_core.tools import ToolSpec
from app.ai.subagents.query.tools._shared import (
    ToolArgumentError,
    caller_role,
    envelope,
    optional_int,
    optional_str,
    resolve_parent,
)
from app.features.questions import service as questions_service

NAME = "list_bank_questions"
DESCRIPTION = (
    "查询题库里的题目（仅家长）。可按学科、年级、知识点、题型、关键词过滤，"
    "返回题目列表（含每题被任务引用的复用次数）。用于「我题库里有哪些一元二次方程的题」"
    "「三年级语文题库有几道」。"
)

_MAX_LIMIT = 200


async def handler(args: dict[str, Any], *, ctx: SubAgentContext, session: Any = None) -> Any:
    # 仅家长：题库是家长私有出题素材池，娃娃端直接失败——既避免「拿别人题库」，
    # 也避免把家长私有池暴露给娃娃（ADR-008 最小暴露）。娃娃查题走 错题本 / 待复习。
    if caller_role(ctx) == "child":
        raise ToolArgumentError("题库查询仅家长可用；娃娃请在错题本 / 待复习里查自己的题。")

    parent = resolve_parent(session=session, ctx=ctx)

    # 缺席归一（ADR-0040）：strict 模式会替模型补 ""/0，模型也可能自发填 all/none。
    subject = optional_str(args.get("subject"))
    grade = optional_int(args.get("grade"), name="grade")
    knowledge_point = optional_str(args.get("knowledge_point"))
    qtype = optional_str(args.get("qtype"))
    keyword = optional_str(args.get("keyword"))
    since_days = optional_int(args.get("since_days"), name="since_days")
    if since_days is not None and since_days < 0:
        raise ToolArgumentError("since_days 不能为负数")
    limit = optional_int(args.get("limit"), name="limit")
    if limit is not None:
        limit = min(limit, _MAX_LIMIT)

    items = questions_service.list_bank_questions(
        session=session,
        parent_id=parent.id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        keyword=keyword,
        since_days=since_days,
        limit=limit,
    )
    # 题库是家长私有池、非按娃娃分组的资源：用合成块承载，复用统一信封形状。
    block = {
        "id": "bank",
        "name": "题库",
        "grade": None,
        "items": items,
        "meta": {"parent_id": str(parent.id)},
    }
    return envelope([block])


SPEC = ToolSpec(
    name=NAME,
    label="查询题库",
    description=DESCRIPTION,
    schema={
        "type": "object",
        "properties": {
            "subject": {
                "type": "string",
                "description": (
                    "学科过滤；取值须与题库里存储的一致（如 数学 / 语文 / 英语），"
                    "不要加「题」等后缀；不传或传空字符串＝全部学科。"
                ),
            },
            "grade": {
                "type": "integer",
                "description": "年级过滤（如 2 表示二年级）；0 或空＝不限年级。",
            },
            "knowledge_point": {
                "type": "string",
                "description": (
                    "知识点过滤；必须与题库中该知识点的**原文完全一致**（如「一元二次方程」），"
                    "不要改写、缩写或加修饰语；空＝不限。"
                ),
            },
            "qtype": {
                "type": "string",
                "description": (
                    "题型过滤；填题库里的 qtype 原值（如 calc / choice），不要翻译为中文；空＝不限。"
                ),
            },
            "keyword": {
                "type": "string",
                "description": "关键词模糊匹配题干或知识点；空＝不匹配。",
            },
            "since_days": {
                "type": "integer",
                "description": (
                    "相对天数过滤：只返回最近 N 天内创建的题目（按 created_at 推算，含今天）；"
                    "如「近三天」传 3、「本月」传 30。0 或空＝不限时间。"
                ),
            },
            "limit": {
                "type": "integer",
                "description": f"最多返回多少道题（0 或空＝不限，上限 {_MAX_LIMIT}）。",
            },
        },
        "required": [],
    },
    handler=handler,
)
