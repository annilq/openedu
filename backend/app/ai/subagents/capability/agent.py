"""能力自述与超范围引导 SubAgent（ADR-0079 / ADR-0097）。

当用户问「你能做什么 / 你会什么 / 怎么用你」或明显超出助手范围时，主动说明职责边界
并给出一个可点方向。本 subagent **不声明任何工具、不调用 provider**：命中即返回服务端
固定能力清单 + 职责边界，全程零 LLM 调用——避免「你能查什么」这类元问题被
``requires_tool_data`` 的硬失败拦截（那会重新打开「模型编造数字」的口子）。

事件轨：直接 yield 一段 ``ASSISTANT_MESSAGE``（固定文本），由 runtime 包裹 run_started/done。
零工具 → runtime 走一次性 ``run``（``run_with_tools`` 在 ``tools==[]`` 时直接转发
``agent.run``），不触发任何模型往返。

ADR-0097：能力清单改为**从 manifests 生成**（原先是手抄的角色清单）。手抄清单与真实
拓扑漂移是既存事故——query/guide 解散后旧清单仍在向用户描述「查询学情 / 引导发布」。
manifest 的 ``name`` + ``description`` 本就是「这个业务能做什么」的权威表述，按 role
过滤可见 business 后投影即得清单；新增/调整业务只需改 manifest，此处自动跟随。
"""
from __future__ import annotations

from functools import lru_cache
from typing import Any, AsyncIterator

from agent_core.protocol import assistant_message
from agent_core.registry import SubAgentManifest, discover_subagent_manifests
from agent_core.subagent import BaseSubAgent, SubAgentContext

# 职责边界（固定常量，单一事实源）：放在清单最前，按角色分叉。
# ADR-0097 同步改写：写操作的出口从「引导到页面」变为「AI 起草 + 会话内确认卡」。
# 学生端不提「起草任务」——create_draft 在 handler 内按角色拒绝，边界话术不得
# 暗示一个用不了的能力（旧 guide 的话术正是这么误导的）。
_BOUNDARY_TEACHER = (
    "我可以帮你起草任务与题目；发布前会请你确认。"
    "除此之外我只做学习相关的事，不能代做题，也不会改你的数据。"
)
_BOUNDARY_STUDENT = (
    "我可以按知识点给你出练习题、讲解不会的题、一起复习错题。"
    "我只做学习相关的事，不能代做题，也不会改你的数据。"
)


@lru_cache(maxsize=1)
def _manifests() -> dict[str, SubAgentManifest]:
    """按需发现（带缓存）：能力清单的单一事实源就是 manifests 本身。

    刻意**不在构造期注入** manifests：``build_subagent`` 是内核通用签名
    （provider / retriever），为单个业务 agent 加参数会污染内核；发现本身是
    纯扫描（importlib 有模块缓存），配 lru_cache 后重复调用零成本。
    """
    return discover_subagent_manifests()


def capability_catalog(role: str) -> list[str]:
    """能力清单 = manifests 按角色的投影（ADR-0097，非 LLM 生成）。

    规则：跳过 ``capability`` 自身（它正在回答「你能做什么」）；按 ``role`` 过滤
    可见 business；按 priority 降序呈现（与路由优先级一致，主能力在前）；每条取
    manifest 的 ``name`` + ``description``。

    不列工具名：工具挂在 agent 实例上（出题 tool 还需 provider 闭包），manifest
    才是路由元数据的单一事实源；其描述文本已覆盖工具能力。角色差异（学生只看
    自己、写工具仅教师）由工具层强制执行，不在清单里二次描述。
    """
    lines: list[str] = []
    for m in sorted(_manifests().values(), key=lambda m: -m.priority):
        if m.business == "capability" or role not in m.roles:
            continue
        lines.append(f"{m.name}：{m.description}")
    return lines


def capability_response(role: str) -> str:
    """职责边界 + 角色能力清单的固定回复文本。"""
    student = (role or "").strip().lower() == "student"
    lines = [_BOUNDARY_STUDENT if student else _BOUNDARY_TEACHER, "", "你可以让我："]
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
