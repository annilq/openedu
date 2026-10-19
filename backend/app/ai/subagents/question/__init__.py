"""题库与出题 SubAgent 包入口（ADR-0097）。"""
from app.ai.subagents.question.agent import QuestionSubAgent
from app.ai.subagents.tasks.generation.specs import (
    build_question_context,
    expand_specs,
    parse_specs_from_text,
)

__all__ = [
    "QuestionSubAgent",
    "expand_specs",
    "build_question_context",
    "parse_specs_from_text",
]
