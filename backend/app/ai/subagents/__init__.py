"""业务 SubAgent 包（ADR-0021 / 0024 / 0031）：业务维度 = SubAgent，学科维度 = Persona。

各 SubAgent 以文件夹 ``<business>/`` 组织（agent.py + manifest.py + tools/ + skills/），
由 agent_core.AgentRuntime 统一发现加载。本包仅做业务层聚合导出；契约基类与注册表来自
agent_core（业务无关），本包不直接持有 base/registry 实现。
"""
from agent_core.registry import (
    SubAgentManifest,
    build_subagent,
    get_subagent_class,
)
from agent_core.subagent import BaseSubAgent, SubAgentContext, ToolCallPair
from app.ai.subagents.query import QuerySubAgent
from app.ai.subagents.question import QuestionSubAgent
from app.ai.subagents.subject_personas import (
    SubjectPersona,
    get_subject_persona,
    normalize_subject,
)
from app.ai.subagents.tutor import TutorSubAgent, detect_subject

__all__ = [
    "BaseSubAgent",
    "SubAgentContext",
    "ToolCallPair",
    "SubAgentManifest",
    "build_subagent",
    "get_subagent_class",
    "SubjectPersona",
    "get_subject_persona",
    "normalize_subject",
    "QuestionSubAgent",
    "TutorSubAgent",
    "QuerySubAgent",
    "detect_subject",
]
