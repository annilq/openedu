"""业务 SubAgent 包（ADR-0021 / 0024 / 0031 / 0097）：业务维度 = SubAgent，学科维度 = Persona。

各 SubAgent 以文件夹 ``<business>/`` 组织（agent.py + manifest.py + tools/ + skills/），
由 agent_core.AgentRuntime 统一发现加载。本包仅做业务层聚合导出；契约基类与注册表来自
agent_core（业务无关），本包不直接持有 base/registry 实现。

ADR-0097 起业务面重组为四个能力域：``tasks``（学情）/ ``question``（题库与出题）/
``students``（人群）/ ``tutor``（伴学），外加零 LLM 的 ``capability``（能力自述）。
原 ``query``（只读查询）解散、功能按域迁入上述业务 agent；原 ``guide``（写意图引导）
删除、写意图由 ``tasks`` 的 ``create_draft``（只起草 + 确认卡发布）承接。
"""
from agent_core.registry import (
    SubAgentManifest,
    build_subagent,
    get_subagent_class,
)
from agent_core.subagent import BaseSubAgent, SubAgentContext, ToolCallPair
from app.ai.subagents.capability import CapabilitySubAgent
from app.ai.subagents.question import QuestionSubAgent
from app.ai.subagents.students import StudentsSubAgent
from app.ai.subagents.subject_personas import (
    SubjectPersona,
    get_subject_persona,
    normalize_subject,
)
from app.ai.subagents.tasks import TasksSubAgent
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
    "TasksSubAgent",
    "StudentsSubAgent",
    "CapabilitySubAgent",
    "detect_subject",
]
