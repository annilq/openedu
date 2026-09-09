"""SubAgent 注册表（ADR-0021 / 0024）。

业务键 → SubAgent 类。经文件夹化后，各 SubAgent 位于
``app/ai/subagents/<business>/agent.py``，由 AgentRuntime 的文件夹发现统一加载；
本注册表保留「业务键 → 类」的显式映射作为发现兜底（新增文件夹后在此登记一行即可）。
"""
from __future__ import annotations

from app.ai.subagents.base import BaseSubAgent
from app.ai.subagents.question import QuestionSubAgent
from app.ai.subagents.tasks import TasksQuerySubAgent
from app.ai.subagents.tutor import TutorSubAgent


class SubAgentRegistry:
    def __init__(self) -> None:
        self._agents: dict[str, type[BaseSubAgent]] = {}

    def register(self, agent_cls: type[BaseSubAgent]) -> None:
        self._agents[agent_cls.business] = agent_cls

    def get(self, business: str) -> type[BaseSubAgent] | None:
        return self._agents.get(business)


_REGISTRY = SubAgentRegistry()
_REGISTRY.register(QuestionSubAgent)
_REGISTRY.register(TutorSubAgent)
_REGISTRY.register(TasksQuerySubAgent)


def get_subagent_class(business: str) -> type[BaseSubAgent] | None:
    """业务键 → SubAgent 类；未知业务返回 None（调用方决定兜底）。"""
    return _REGISTRY.get(business)


def build_subagent(
    business: str, *, provider, retriever=None, engine=None
) -> BaseSubAgent | None:
    """业务键 → SubAgent 实例；未知业务返回 None（调用方决定兜底）。"""
    agent_cls = _REGISTRY.get(business)
    if agent_cls is None:
        return None
    return agent_cls(provider=provider, retriever=retriever, engine=engine)


__all__ = [
    "SubAgentRegistry",
    "get_subagent_class",
    "build_subagent",
    "QuestionSubAgent",
    "TutorSubAgent",
    "TasksQuerySubAgent",
]
