"""业务 SubAgent 基类与共享上下文（ADR-0021）。

每个业务 SubAgent 暴露统一契约 ``handle(intent, ctx) -> result``，使轻主管（路由显式派发）
能无差别地调用任意业务；未来也可平滑插入 LLM 意图分类升级为完整 supervisor，
无需改动各 SubAgent 实现。
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any


@dataclass
class SubAgentContext:
    """一次 SubAgent 调用的共享上下文。学科 persona 由 SubAgent 内部据 subject 取，无需外部传。"""

    subject: str = ""
    grade: int = 0
    knowledge_point: str = ""
    context: str | None = None
    question: str | None = None
    child_id: object | None = None
    parent_id: object | None = None
    model: str | None = None
    allowed_subjects: list[str] | None = None
    extra: dict[str, Any] = field(default_factory=dict)


class BaseSubAgent(ABC):
    # 业务键（注册表索引）：question / tutor / grader / diagnosis / planner / report …
    business: str = "base"

    def __init__(self, *, provider, retriever=None) -> None:
        # provider: 业务层统一 LLM 抽象（LLMProvider）；retriever: 可选知识库检索。
        self.provider = provider
        self.retriever = retriever

    @abstractmethod
    async def handle(self, intent: dict, ctx: SubAgentContext) -> Any:
        """处理一次业务请求，返回业务结果（类型由子类定义）。"""
        ...
