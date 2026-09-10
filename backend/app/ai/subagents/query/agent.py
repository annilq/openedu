"""学情查询 SubAgent（ADR-0033 / 文件夹化）：只读业务查询的唯一入口。

家长说「我的任务有哪些 / 小明最近错题多吗」、娃娃说「今天有什么作业」时由 runtime
路由到此（``priority=12``，接住原 ``tasks`` 为抢「任务题目」而设的权重）。与另两个
subagent 的关键差异：**本 subagent 声明真实工具**（``tools=QUERY_TOOLS``），
runtime 走 ``run_with_tools`` 的 tool loop 调度，模型经原生 function calling 选型，
执行权仍在内核（ADR-0033 决策 2）。

事件轨：
- ``THINKING``：模型推理增量；
- ``TOOL_CALL`` / ``TOOL_RESULT``：由 runtime 产出，原始载荷落库回放；
- ``DATA``：本 subagent 经 ``render_tool_result`` 补发的展示卡（决策 11，前端零改动）；
- ``ASSISTANT_MESSAGE``：模型收尾结论。

业务边界（``parent_id`` / ``child_id`` / ``role``）全部走 ``SubAgentContext``；
内核与适配器不感知任何教育语义。角色裁剪不在本文件——工具出参先过
``_shared.project_for_role``，本文件只负责提示词与展示投影。
"""
from __future__ import annotations

from typing import Any, AsyncIterator

from agent_core.protocol import data_event
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools
from app.ai.subagents.query.render import render_cards
from app.ai.subagents.query.tools.registry import QUERY_TOOLS

_SYSTEM = """你是「学情查询」助手，只负责查询本家庭的学习数据，并用中文简洁作答。

规则：
- 只依据工具返回的数据回答，绝不编造数字、题目、姓名或日期；数据为空就如实说「没有查到」。
- 需要定位某个娃娃时先调用 list_children 拿 child_id，再带 id 查明细；不确定就先问清对象。
- 一次问题只调必要的工具，不要重复调用同一个工具；同一轮需要多项数据时可并行调多个工具。
- 用一两句话概括结论，不要复述原始 JSON 字段，也不要罗列全部明细。
- 只读：不要声称能修改任务、派发作业或代答题目；需要写操作时引导用户去对应页面。
- 与学情数据无关的请求（闲聊、解题、出题）不要用查询工具硬凑，直接说明你能查什么。"""

_CHILD_HINT = (
    "当前提问者是**娃娃本人**：只能查询他自己的数据，不要提及其他娃娃，"
    "也不得输出任何题目的答案或解析。"
)
_PARENT_HINT = "当前提问者是**家长**：可以查询名下所有娃娃的数据（含答案与解析，仅限本家庭）。"


class QuerySubAgent(BaseSubAgent):
    business = "query"

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        # opt-in 真实工具：非空即触发 runtime 的 tool loop（agent_core.subagent.run_with_tools）。
        self.tools = list(QUERY_TOOLS)

    # ── tool loop 的初轮消息 ──
    def initial_system(self, message: str, ctx: SubAgentContext) -> str:
        role = (ctx.role or "").strip().lower()
        parts = [_SYSTEM, _CHILD_HINT if role == "child" else _PARENT_HINT]
        if ctx.skills:
            parts.append(ctx.skills)
        return "\n\n".join(p for p in parts if p)

    def initial_user(self, message: str, ctx: SubAgentContext) -> str:
        return message

    # ── 展示投影（决策 11）：TOOL_RESULT 存原始，DATA 帧供前端渲染 ──
    def render_tool_result(self, name: str, result: Any) -> list[Any]:
        return [data_event(card, extra={"type": "query"}) for card in render_cards(name, result)]

    # ── 直接调用入口 ──
    async def run(
        self, message: str, ctx: SubAgentContext, *, session: Any = None
    ) -> AsyncIterator[Any]:
        """runtime 主路径走 ``run_with_tools(self, …)``（本 subagent tools 恒非空）。

        本方法仅为「有人绕过 runtime 直接 ``agent.run(...)``」兜底：委托同一套 tool loop，
        保证两条路径行为一致（含轮次上限与硬失败），不复制一份编排。
        """
        if not self.tools:
            # 结构性自检：tools 为空说明装配出错（真实路径不允许静默退化成纯聊天）。
            yield self._finish("学情查询暂不可用，请稍后重试。", blocked=True)
            return
        async for ev in run_with_tools(self, message, ctx, session=session):
            yield ev


__all__ = ["QuerySubAgent"]
