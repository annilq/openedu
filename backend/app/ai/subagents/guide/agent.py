"""``guide`` 任务引导 SubAgent（写意图的出口，不用模型）。

**为什么需要它**：``query`` 的 ``triggers`` 含泛词「任务 / 作业」且 ``priority=12`` 最高，
于是「帮我创建一个任务」这类**写意图**也被它接住；而 ``query`` 是只读的（``QUERY_TOOLS``
全是 SELECT 语义，提示词也写死「写操作引导用户去对应页面」），结果用户只能拿到一句
「我这边只能查询」——他没有得到任何可用的下一步。

本 subagent 在路由层把写意图**从只读查询手里接走**（``priority=20``），直接产出
一张带**受控跳转动作**的引导卡：说明为什么不能代做 + 给一个点得到的出口。

**刻意不持有工具、也不需要模型**：它没有任何信息要查，答案在代码里就是确定的。
让模型自由生成这段文案只会带来「它又开始编页面名」的风险，而引导正确的唯一标准
是**跳转目标正确**——那是编译期常量，不是生成结果。
"""
from __future__ import annotations

from typing import Any, AsyncIterator

from agent_core.protocol import data_event
from agent_core.subagent import BaseSubAgent, SubAgentContext

# 引导卡种类（进信封的 `data.type`）。与前端 `AssistantCardKind.guide` 逐字对齐；
# 与 `query/render.py#_KIND` 里那些「工具 → 种类」不同，本卡**不来自工具结果**，
# 由本 subagent 直接产出，故不登记在那张表里（ADR-0042 的登记规则针对工具投影）。
KIND = "guide"

# 受控跳转目标（线协议常量，前端 `ShellDestination.fromTarget` 是唯一的解读者）。
#
# 值域刻意是**枚举而非 URL**：助手在服务端，导航在客户端（且家长端助手是 push 的整页，
# 娃娃端是壳内页签，同一个目标在两端落点不同）。下发 URL 等于让服务端描述客户端导航，
# 也把 ADR-0042「不做服务端 UI schema」那条线一起越过了。
TARGET_CREATE_TASK = "parent_create_task"
TARGET_QUESTION_BANK = "parent_question_bank"

# 收尾话术：说清「为什么不能」——只回「我不能创建」而不给理由，用户只会再问一遍。
_FINISH = (
    "布置任务要由你亲自定题并确认发布，助手这边只负责出题和查数据，"
    "不能代你创建或派发。入口在下面。"
)

_CARD_TEXT = "到「布置任务」页选好题目，确认后发布给娃娃。"


class GuideSubAgent(BaseSubAgent):
    business = "guide"

    async def run(
        self, message: str, ctx: SubAgentContext, *, session: Any = None
    ) -> AsyncIterator[Any]:
        yield data_event(
            {
                "title": "布置任务",
                "text": _CARD_TEXT,
                "actions": [
                    {"label": "去布置任务", "target": TARGET_CREATE_TASK},
                    {"label": "先看看题库", "target": TARGET_QUESTION_BANK},
                ],
            },
            extra={"type": KIND},
        )
        yield self._finish(_FINISH)


__all__ = [
    "GuideSubAgent",
    "KIND",
    "TARGET_CREATE_TASK",
    "TARGET_QUESTION_BANK",
]
