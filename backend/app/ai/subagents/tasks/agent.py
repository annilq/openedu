"""任务查询 SubAgent（ADR-0024 / 文件夹化）：查任务题目。

家长说「查看任务题目 / 列出作业」时由 runtime 路由到此；复用 shared_tool
``list_tasks``（app/ai/tools）列出草稿任务及其题目，以 DATA 呈现。
"""
from __future__ import annotations

from app.ai.runtime.protocol import data_event
from app.ai.subagents.base import BaseSubAgent, SubAgentContext
from app.ai.tools import list_tasks


class TasksQuerySubAgent(BaseSubAgent):
    business = "tasks"

    async def run(self, message: str, ctx: SubAgentContext, *, session=None):
        if session is None:
            yield self._finish("暂无可查询的会话上下文。")
            return
        tc = self._tool("list_tasks", label="查询任务题目")
        yield tc.call
        rows = list_tasks(session, parent_id=ctx.parent_id)
        yield tc.result({"count": len(rows)})

        if not rows:
            yield self._finish("你还没有草稿任务。可以说「帮我出 3 道三年级分数选择题」来生成。")
            return

        for row in rows:
            yield data_event("done", "task", row)
        total = sum(len(r["questions"]) for r in rows)
        yield self._finish(
            f"共 {len(rows)} 个草稿任务、{total} 道题。点击任务卡可查看题目与答案。"
        )
