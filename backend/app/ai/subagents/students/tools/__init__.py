"""students（人群域）业务 agent 的工具注册表（ADR-0097）。"""
from __future__ import annotations

from agent_core.tools import ToolSpec

from .list_students import SPEC as LIST_STUDENTS

STUDENTS_TOOLS: list[ToolSpec] = [LIST_STUDENTS]

__all__ = ["STUDENTS_TOOLS"]
