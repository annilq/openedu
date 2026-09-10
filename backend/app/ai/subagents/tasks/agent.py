"""任务查询 SubAgent（ADR-0024 / 文件夹化）：查任务题目。

家长说「查看任务题目 / 列出作业」时由 runtime 路由到此；复用 shared_tool
``list_tasks``（app/ai/tools）列出草稿任务及其题目，以 DATA 帧呈现。
业务字段（parent_id / session）走 agent_core 的 ``SubAgentContext.extra``，core 不感知。

注：agent_core 的真实 tool loop（Step 3）由 ``agent_core.subagent.run_with_tools`` 提供，
并以独立契约测试覆盖；本生产 subagent 选择一次性直接调用（tools=[]），以保留
DATA 任务卡这一前端既有消费契约（TOOL_RESULT 不携带题卡结构化载荷）。
"""
from __future__ import annotations

from agent_core.protocol import data_event
from agent_core.subagent import BaseSubAgent, SubAgentContext
from app.ai.tools import list_tasks


class TasksQuerySubAgent(BaseSubAgent):
    business = "tasks"

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        parent_id = ctx.extra.get("parent_id")
        if parent_id is None:
            yield self._finish("暂无可查询的会话上下文。")
            return
        rows = list_tasks(session, parent_id=parent_id)
        if not rows:
            yield self._finish("你还没有草稿任务。可以说「帮我出 3 道三年级分数选择题」来生成。")
            return
        for row in rows:
            yield data_event(row, extra={"type": "task"})
        total = sum(len(r["questions"]) for r in rows)
        yield self._finish(
            f"共 {len(rows)} 个草稿任务、{total} 道题。点击任务卡可查看题目与答案。"
        )
