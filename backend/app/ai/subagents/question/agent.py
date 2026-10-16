"""题库与出题 SubAgent（ADR-0097：原出题 agent 改造为 tool loop agent）。

business 键保持 ``question``（契约测试的动作归属 ``task_generate``、ADR-0095
slot filling 的分组键、历史会话 ``kind`` 都不变），语义从「出题助手」扩大为
「题库与出题助手」——目录名沿用 ``question/`` 是历史原因，manifest.name 才是
对外名称。

执行模型从**约束解码 run()** 改为 **tool loop**（用户拍板「出题降级为 tool」）：

- ``generate_questions`` 是**流式** tool（``stream_handler``）：STEP / THINKING /
  DATA 帧逐帧外发，末帧 ToolOutcome 带「应出 / 实出 / 失败」计数回灌，收尾话术
  由 tool loop 第二轮的模型据实生成——流式体验不丢，且比原 run() 直接吐固定
  文案更贴合「结论必须有据」（ADR-0033）。
- 出题规格优先取 ``ctx.extra["specs"]``（ADR-0095 slot filling 结构化规格），
  不到 model 侧传话；无 specs 时才由模型从 args 给规格。
- 其余三个工具管题库 CRUD：list / delete / archive。删除不可逆，两步模式
  （先 list 展示、用户点名再删）；归档可逆，优先引导归档。

``requires_tool_data=True``：整轮零工具调用却给正文＝编题/编数据，硬失败拦截
（ADR-0033）。元问题（「你能做什么」）由 capability 在路由层接走，不进本 agent。
"""
from __future__ import annotations

from typing import Any, AsyncIterator

from agent_core.protocol import data_event
from agent_core.subagent import BaseSubAgent, SubAgentContext, run_with_tools
from app.ai.shared.render import render_cards
from app.ai.subagents.question.tools import questions_tools
from app.features.assistant.kp_focus import format_kp_focus

_SYSTEM = """你是「题库与出题」助手，帮教师管理题库、按规格出题。用中文简洁作答。

规则：
- **出题**：调用 generate_questions，把用户说的科目/年级/题型/数量/知识点如实填进参数；
  规格可能已由系统备好（工具内部优先使用），不要自行改写或编造题目内容。
- **收尾话术**：据工具返回的计数如实汇报——应出几道、实出几道、失败几道及原因；
  少出题必须说明，不许把残缺说成完整。多学科时列出各科数量（如「数学 1 道、
  语文 1 道」），不得只报第一科。
- **题库查询**：用户问「题库里有什么题」时调 list_bank_questions 查出来展示，
  不要只反问「要不要我帮你查」。
- **删除不可逆**：必须先调 list_bank_questions 让用户看到题、且用户明确点名要删，
  才可调 delete_questions；用户说「收起来 / 先不管」时用 archive_questions（可逆），
  不要主动建议删除。
- 只依据工具返回的数据回答，绝不编造数字、题目、姓名或日期；数据为空就如实说「没有查到」。
- 需要定位某个学生时用 student_name（昵称）直接查明细；只有昵称有歧义时才先调
  list_students 拿 id。
- 与题库/出题无关的请求（闲聊、解题、查学情）不要硬凑，直接说明你能做什么。"""

_CHILD_HINT = (
    "当前提问者是**学生本人**：题库管理与删除/归档对其不可用（工具会拒绝）。"
    "学生可以出题自练；不得输出任何题目的答案或解析。"
)
_TEACHER_HINT = "当前提问者是**教师**：可查询名下学生数据、管理自己的题库并出题（含答案与解析，仅限本家庭）。"


class QuestionSubAgent(BaseSubAgent):
    business = "question"

    # 结论必须有据（ADR-0033）：每一句结论都得来自工具数据（出题计数 / 题库查询结果）。
    requires_tool_data = True

    def __init__(self, *, provider, retriever=None) -> None:
        super().__init__(provider=provider, retriever=retriever)
        # 出题 tool 需要 provider（流式生成），故在装配期构造。
        self.tools = questions_tools(provider=provider, retriever=retriever)

    # ── tool loop 的初轮消息 ──
    def initial_system(self, message: str, ctx: SubAgentContext) -> str:
        role = (ctx.role or "").strip().lower()
        parts = [_SYSTEM, _CHILD_HINT if role == "student" else _TEACHER_HINT]
        # ADR-0080：知识点聚焦段（强调须依托工具数据，维持 requires_tool_data 契约）。
        focus_seg = format_kp_focus(ctx.extra.get("knowledge_point"), query_mode=True)
        if focus_seg:
            parts.append(focus_seg)
        if ctx.skills:
            parts.append(ctx.skills)
        return "\n\n".join(p for p in parts if p)

    def initial_user(self, message: str, ctx: SubAgentContext) -> str:
        return message

    # ── 展示投影（决策 11 / ADR-0042）：TOOL_RESULT 存原始，DATA 帧供前端渲染 ──
    # 流式 tool（generate_questions）的展示帧由 generator 自负，runtime 跳过本 hook。
    def render_tool_result(self, name: str, result: Any) -> list[Any]:
        return [
            data_event(card.payload, extra={"type": card.kind})
            for card in render_cards(name, result)
        ]

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
            yield self._finish("题库与出题暂不可用，请稍后重试。", blocked=True)
            return
        async for ev in run_with_tools(self, message, ctx, session=session):
            yield ev


__all__ = ["QuestionSubAgent"]
