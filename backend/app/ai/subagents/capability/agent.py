"""能力自述与超范围引导 SubAgent（ADR-0079）。

当用户问「你能做什么 / 你会什么 / 怎么用你」或明显超出助手范围时，主动说明职责边界
并给出一个可点方向。本 subagent **不声明任何工具、不调用 provider**：命中即返回服务端
固定能力清单 + 职责边界，全程零 LLM 调用——避免「你能查什么」这类元问题被 ``query`` 的
``requires_tool_data`` 硬失败（那会重新打开「模型编造数字」的口子）。

事件轨：直接 yield 一段 ``ASSISTANT_MESSAGE``（固定文本），由 runtime 包裹 run_started/done。
零工具 → runtime 走一次性 ``run``（``run_with_tools`` 在 ``tools==[]`` 时直接转发
``agent.run``），不触发任何模型往返。
"""
from __future__ import annotations

from typing import Any, AsyncIterator

from agent_core.protocol import assistant_message
from agent_core.subagent import BaseSubAgent, SubAgentContext

# 职责边界（单一事实源，固定常量）：放在清单最前，所有角色共用。
_BOUNDARY = "我只做学习相关的事，不能改数据、不能代做题。"

_STUDENT_CAPABILITIES = [
    "讲解不会的知识点",
    "按知识点出练习题",
    "帮你复习错题 / 看待复习",
    "分析你的掌握度与学习进度",
]

_TEACHER_CAPABILITIES = [
    "查学情（任务 / 错题 / 掌握度 / 进度）",
    "引导你发布任务",
    "围绕某个知识点讲解 / 出题",
]


def capability_catalog(role: str) -> list[str]:
    """服务端固定能力清单（按角色分叉），非 LLM 生成。单一事实源。"""
    if role == "teacher":
        return list(_TEACHER_CAPABILITIES)
    return list(_STUDENT_CAPABILITIES)


def capability_response(role: str) -> str:
    """职责边界 + 角色能力清单的固定回复文本。"""
    lines = [_BOUNDARY, "", "你可以让我："]
    lines.extend(f"· {c}" for c in capability_catalog(role))
    return "\n".join(lines)


class CapabilitySubAgent(BaseSubAgent):
    business = "capability"

    def __init__(self, *, provider, retriever=None) -> None:
        # 不持有工具、不调用 provider（零 LLM）；保留基类签名兼容。
        super().__init__(provider=provider, retriever=retriever)

    async def run(
        self, message: str, ctx: SubAgentContext, *, session: Any = None
    ) -> AsyncIterator[Any]:
        yield assistant_message(capability_response(ctx.role))
