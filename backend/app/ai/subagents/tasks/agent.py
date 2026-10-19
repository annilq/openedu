"""任务学情与出题域 SubAgent（ADR-0097 按域重组 / ADR-0098 三域并入）。

域范围：tasks（任务 / 错题本 / 进度 / 掌握度 / 待复习）+ students（名单，
ADR-0098 吸收）+ questions（题库 CRUD + 流式出题，ADR-0098 吸收）。
「小明最近错题多吗」这类跨子域的聚合问题在本 agent 内闭环——这是选「能力域
粗切」而非按 features 一级目录细切的理由（细切下该问题无处路由）。

执行模型：tool loop（12 个工具：学情读 7 + 名单 1 + 草稿写 1 + 题库 3 +
出题流式 1）。``requires_tool_data=True``（结论必须有据，ADR-0033；元问题由
capability 在路由层接走）。

出题是唯一的**流式** tool（``generate_questions``，ADR-0097 起由约束解码
run() 降级）：执行期间逐题推送 STEP / DATA 帧，末帧 ToolOutcome 计数回灌，
收尾话术由 tool loop 第二轮的模型据实生成。

写操作只有 ``create_draft`` 一个且**只起草**：建 draft 态任务，确认与派发
由用户在确认卡上点「确认发布」完成（前端直走 REST，ADR-0097 §2.3）。题库侧
删除不可逆（两步模式） / 归档可逆。学生端写工具在 handler 内按角色拒绝；
读工具学生只看到自己的数据。
"""
from __future__ import annotations

from typing import Any, AsyncIterator

from agent_core.protocol import data_event
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools
from app.ai.shared.render import render_cards
from app.ai.subagents.tasks.tools import (
    BANK_TOOLS,
    TASKS_TOOLS,
    generation_tools,
)
from app.ai.subagents.tasks.tools.create_draft import draft_card
from app.features.assistant.kp_focus import format_kp_focus

_SYSTEM = """你是「任务学情与出题」助手，帮教师/学生查学情、组建草稿任务、管理题库并按规格出题。用中文简洁作答。

规则：
- 只依据工具返回的数据回答，绝不编造数字、题目、姓名或日期；数据为空就如实说「没有查到」。
- 需要定位某个学生时用 student_name（昵称）**直接查明细**，不必先取 student_id；
  只有昵称有歧义（命中多个学生）时才先调 list_students 拿 id。不确定对象就先问清。
- 一次问题只调必要的工具，不要重复调用同一个工具；同一轮需要多项数据时可并行调多个工具。
- 用一两句话概括结论，不要复述原始 JSON 字段，也不要罗列全部明细。
- 用户想**选题 / 找参考题 / 看题库**时直接查出来给他，不要只反问「要不要我帮你查」。
- **创建任务只到草稿为止**：调 create_draft 建 draft 态任务，告诉用户「已在下方
  生成草稿，确认后点发布」。不要声称已派发——派发由用户在确认卡上完成。
- **出题**：调用 generate_questions，把用户说的科目/年级/题型/数量/知识点如实填进参数；
  规格可能已由系统备好（工具内部优先使用），不要自行改写或编造题目内容。
- **收尾话术**：据工具返回的计数如实汇报——应出几道、实出几道、失败几道及原因；
  少出题必须说明，不许把残缺说成完整。多学科时列出各科数量（如「数学 1 道、
  语文 1 道」），不得只报第一科。
- **删除不可逆**：必须先调 list_bank_questions 让用户看到题、且用户明确点名要删，
  才可调 delete_questions；用户说「收起来 / 先不管」时用 archive_questions（可逆），
  不要主动建议删除。
- 与学情 / 题库 / 出题无关的请求（闲聊、解题）不要硬凑，直接说明你能做什么。"""

_CHILD_HINT = (
    "当前提问者是**学生本人**：只能查询他自己的数据，不得提及其他学生，"
    "也不得输出任何题目的答案或解析；创建任务等写操作对其不可用。"
    "可以按知识点出题自练（ADR-0081 §2.2）。"
)
_TEACHER_HINT = (
    "当前提问者是**教师**：可以查询名下所有学生的数据（含答案与解析，仅限本家庭），"
    "管理自己的题库并出题，还可从题库组建草稿任务。"
)


class TasksSubAgent(BaseSubAgent):
    business = "tasks"

    # 结论必须有据（ADR-0033）：每一句结论都得来自工具数据。整轮零工具调用却给出
    # 正文＝模型在编（真机：本地小模型流式下直接编出「3 个学生 / 掌握度 85%」），
    # 此时由 runtime 硬失败拦截，而不是把编造内容下发给用户。
    requires_tool_data = True

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        # 出题 tool 需要 provider（流式生成），故在装配期经闭包工厂构造；
        # 其余 11 个同步工具模块级已构造。ADR-0098：question 域三组工具并入。
        self.tools = [
            *TASKS_TOOLS,
            *BANK_TOOLS,
            *generation_tools(provider=provider, retriever=retriever),
        ]

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
