"""任务学情域 SubAgent（ADR-0097：query 解散后按域重组的新业务 agent）。

域范围：tasks（任务 / 错题本 / 进度）+ review（待复习）+ mastery（掌握度）。
「小明最近错题多吗」这类跨子域的聚合问题在本 agent 内闭环——这是选「能力域
粗切」而非按 features 一级目录细切的理由（细切下该问题无处路由）。

执行模型：tool loop（8 个同步工具，无流式执行体）。``requires_tool_data=True``
（结论必须有据，ADR-0033；元问题由 capability 在路由层接走）。

ADR-0098：``list_students`` 自 students 域吸收（原单工具域的存在理由是路由边界，
现由 tasks 的名单 triggers 承接）；出题与题库工具在第二波并入。

写操作只有 ``create_draft`` 一个且**只起草**：建 draft 态任务，确认与派发
由用户在确认卡上点「确认发布」完成（前端直走 REST，ADR-0097 §2.3）。学生端
写工具在 handler 内按角色拒绝；读工具学生只看到自己的数据。
"""
from __future__ import annotations

from typing import Any, AsyncIterator

from agent_core.protocol import data_event
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools
from app.ai.shared.render import render_cards
from app.ai.subagents.tasks.tools import TASKS_TOOLS
from app.ai.subagents.tasks.tools.create_draft import draft_card
from app.features.assistant.kp_focus import format_kp_focus

_SYSTEM = """你是「任务学情」助手，帮教师/学生查学情、并从题库组建草稿任务。用中文简洁作答。

规则：
- 只依据工具返回的数据回答，绝不编造数字、题目、姓名或日期；数据为空就如实说「没有查到」。
- 需要定位某个学生时用 student_name（昵称）**直接查明细**，不必先取 student_id；
  只有昵称有歧义（命中多个学生）时才先调 list_students 拿 id。不确定对象就先问清。
- 一次问题只调必要的工具，不要重复调用同一个工具；同一轮需要多项数据时可并行调多个工具。
- 用一两句话概括结论，不要复述原始 JSON 字段，也不要罗列全部明细。
- 用户想**选题 / 找参考题**时直接查出来给他，不要只反问「要不要我帮你查」。
- **创建任务只到草稿为止**：调 create_draft 建 draft 态任务，告诉用户「已在下方
  生成草稿，确认后点发布」。不要声称已派发——派发由用户在确认卡上完成。
- 与学情数据无关的请求（闲聊、解题、出题）不要用查询工具硬凑，直接说明你能查什么。"""

_CHILD_HINT = (
    "当前提问者是**学生本人**：只能查询他自己的数据，不得提及其他学生，"
    "也不得输出任何题目的答案或解析；创建任务等写操作对其不可用。"
)
_TEACHER_HINT = "当前提问者是**教师**：可以查询名下所有学生的数据（含答案与解析，仅限本家庭）。"


class TasksSubAgent(BaseSubAgent):
    business = "tasks"

    # 结论必须有据（ADR-0033）：每一句结论都得来自工具数据。整轮零工具调用却给出
    # 正文＝模型在编（真机：本地小模型流式下直接编出「3 个学生 / 掌握度 85%」），
    # 此时由 runtime 硬失败拦截，而不是把编造内容下发给用户。
    requires_tool_data = True

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        self.tools = list(TASKS_TOOLS)

    # ── tool loop 的初轮消息 ──
    def initial_system(self, message: str, ctx: SubAgentContext) -> str:
        role = (ctx.role or "").strip().lower()
        parts = [_SYSTEM, _CHILD_HINT if role == "student" else _TEACHER_HINT]
        # ADR-0080：知识点聚焦段（query 额外强调须依托工具数据，维持契约）。
        focus_seg = format_kp_focus(ctx.extra.get("knowledge_point"), query_mode=True)
        if focus_seg:
            parts.append(focus_seg)
        if ctx.skills:
            parts.append(ctx.skills)
        return "\n\n".join(p for p in parts if p)

    def initial_user(self, message: str, ctx: SubAgentContext) -> str:
        return message

    # ── 展示投影（决策 11 / ADR-0042）：TOOL_RESULT 存原始，DATA 帧供前端渲染 ──
    def render_tool_result(self, name: str, result: Any) -> list[Any]:
        # 草稿任务的确认卡：读工具走统一投影，写工具补发确认卡（confirm/assign
        # 由前端按钮直走 REST，不新造 AI 确认机制）。
        if name == "create_draft" and isinstance(result, dict):
            block = (result.get("students") or [{}])[0]
            item = (block.get("items") or [{}])[0]
            if item.get("task_id"):
                return [draft_card(item)]
        return [
            data_event(card.payload, extra={"type": card.kind})
            for card in render_cards(name, result)
        ]

    # ── 直接调用入口 ──
    async def run(
        self, message: str, ctx: SubAgentContext, *, session: Any = None
    ) -> AsyncIterator[Any]:
        """runtime 主路径走 ``run_with_tools(self, …)``（本 subagent tools 恒非空）。

        本方法仅为「有人绕过 runtime 直接 ``agent.run(...)``」兜底。
        """
        if not self.tools:
            yield self._finish("任务学情暂不可用，请稍后重试。", blocked=True)
            return
        async for ev in run_with_tools(self, message, ctx, session=session):
            yield ev


__all__ = ["TasksSubAgent"]
