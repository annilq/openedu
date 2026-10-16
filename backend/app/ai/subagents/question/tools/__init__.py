"""questions（题库与出题）业务 agent 的工具注册表（ADR-0097）。

出题是**流式** tool（``generate_questions``），provider 装配期闭包注入；
其余三个是同步工具。装配入口 ``questions_tools(provider=..., retriever=...)``
——由 ``QuestionSubAgent.__init__`` 调用（工具要 provider，故不在模块级构造）。
"""
from __future__ import annotations

from agent_core.tools import ToolSpec

from .archive_questions import SPEC as ARCHIVE_QUESTIONS
from .delete_questions import SPEC as DELETE_QUESTIONS
from .generate_questions import make_spec as make_generate_spec
from .list_bank_questions import SPEC as LIST_BANK_QUESTIONS


def questions_tools(*, provider, retriever=None) -> list[ToolSpec]:
    """装配期构造本业务全部工具（出题 tool 需要 provider 闭包）。"""
    return [
        LIST_BANK_QUESTIONS,
        make_generate_spec(provider=provider, retriever=retriever),
        DELETE_QUESTIONS,
        ARCHIVE_QUESTIONS,
    ]


__all__ = ["questions_tools"]
