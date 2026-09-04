"""业务 SubAgent 包（ADR-0021）：业务维度 = SubAgent，学科维度 = Persona 参数。

导入本包即触发 registry 自动注册出题 / 伴学两个 SubAgent（首轮双 SubAgent 验证 seam）。
"""
from app.ai.subagents.base import BaseSubAgent, SubAgentContext
from app.ai.subagents.registry import get_subagent_class
from app.ai.subagents.subject_personas import SubjectPersona, get_subject_persona

__all__ = [
    "BaseSubAgent",
    "SubAgentContext",
    "SubjectPersona",
    "get_subject_persona",
    "get_subagent_class",
]
