"""SubAgent 注册表（ADR-0021）：业务键 → SubAgent 类。

轻主管（路由显式派发）按业务键取 SubAgent；新增业务 = 注册一个新 SubAgent 类，
无需改动其他业务或学科 persona 配置（正交解耦）。未来升级为完整 LLM supervisor 时，
只新增「意图分类 → get_subagent_class(business)」一层，各 SubAgent 不动。
"""
from __future__ import annotations

from app.ai.subagents.base import BaseSubAgent
from app.ai.subagents.question_agent import QuestionSubAgent
from app.ai.subagents.tutor_agent import TutorSubAgent


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


def get_subagent_class(business: str) -> type[BaseSubAgent] | None:
    """业务键 → SubAgent 类；未知业务返回 None（调用方决定兜底）。"""
    return _REGISTRY.get(business)


__all__ = ["SubAgentRegistry", "get_subagent_class", "QuestionSubAgent", "TutorSubAgent"]
