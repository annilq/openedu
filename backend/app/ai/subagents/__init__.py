"""业务 SubAgent 包（ADR-0021 / 0024）：业务维度 = SubAgent，学科维度 = Persona 参数。

各 SubAgent 以文件夹 ``<business>/`` 组织（agent.py + manifest.py + tools/ + skills/），
由 AgentRuntime 统一发现加载；本包暴露契约基类与工厂。
"""
from app.ai.subagents.base import BaseSubAgent, SubAgentContext
from app.ai.subagents.question import QuestionSubAgent
from app.ai.subagents.registry import build_subagent, get_subagent_class
from app.ai.subagents.subject_personas import SubjectPersona, get_subject_persona
from app.ai.subagents.tasks import TasksQuerySubAgent
from app.ai.subagents.tutor import TutorSubAgent

__all__ = [
    "BaseSubAgent",
    "SubAgentContext",
    "SubjectPersona",
    "get_subject_persona",
    "get_subagent_class",
    "build_subagent",
    "QuestionSubAgent",
    "TutorSubAgent",
    "TasksQuerySubAgent",
]

