"""人群域 SubAgent（ADR-0097）。

域范围：students（学生定位）。「我班有哪些学生」「帮我看看娃们」归本域；
教师=名下全部、学生=自己。classes 的建班/改班/删班**不进 AI**（SPEC Out of
Scope：重表单管理，AI 助手价值低，维持纯 REST）。

单工具 agent 看似小题大做，存在的理由是**路由边界**：人群查询若混进 tasks
的 triggers，「有哪些学生」会被学情词表抢走；独立域 + 低 priority 让聚合
问题（「小明最近错题多吗」）仍落 tasks，纯人群问题落本域。
"""
from __future__ import annotations

from typing import Any, AsyncIterator

from agent_core.protocol import data_event
from agent_core.subagent import BaseSubAgent, run_with_tools
from app.ai.shared.render import render_cards
from app.ai.subagents.students.tools import STUDENTS_TOOLS

_SYSTEM = """你是「学生名单」助手，只回答「有哪些学生 / 哪个学生」这类定位问题。

规则：
- 只依据工具返回的数据回答，绝不编造姓名；数据为空就如实说「没有查到」。
- 用户想了解某个学生的明细（错题 / 进度 / 掌握度）时，告诉他可以用自然语言
  直接问（如「小明最近错题多吗」）——本助手只负责名单。
- 与名单无关的请求（闲聊、解题、出题、查学情）不要硬凑，直接说明你能做什么。"""


class StudentsSubAgent(BaseSubAgent):
    business = "students"

    # 结论必须有据（ADR-0033）：名单只能来自工具。
    requires_tool_data = True

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        self.tools = list(STUDENTS_TOOLS)

    def initial_system(self, message: str, ctx: SubAgentContext) -> str:
        parts = [_SYSTEM]
        if ctx.skills:
            parts.append(ctx.skills)
        return "\n\n".join(p for p in parts if p)

    def initial_user(self, message: str, ctx: SubAgentContext) -> str:
        return message

    def render_tool_result(self, name: str, result: Any) -> list[Any]:
        return [
            data_event(card.payload, extra={"type": card.kind})
            for card in render_cards(name, result)
        ]

    async def run(
        self, message: str, ctx: SubAgentContext, *, session: Any = None
    ) -> AsyncIterator[Any]:
        """runtime 主路径走 ``run_with_tools``；本方法仅兜底直调路径。"""
        if not self.tools:
            yield self._finish("学生名单暂不可用，请稍后重试。", blocked=True)
            return
        async for ev in run_with_tools(self, message, ctx, session=session):
            yield ev


__all__ = ["StudentsSubAgent"]
