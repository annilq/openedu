"""AI 调用归一封装（ADR-0034 Phase 2，轻量收敛）。

统一所有「同步 AI 调用」（批改 / 出题重生成）的 provider 构造：

- 一律经 ``resolve_engine`` 解析模型引用，消除「批改忽略 model / ModelConfig」的分裂；
- 单行调用点，未来接 quota / audit 只需改此处，无需散落到各 service / router。

``build_provider`` 仍保留为底层工厂（engine 已解析时直接构造）；本模块是其
「带模型解析」的上层封装。异步 / SSE 路径（AgentRuntime 内）不在此处，由 runtime 统一注入。
"""
from __future__ import annotations

from uuid import UUID

from sqlmodel import Session

from app.ai import resolve_engine
from app.domain import build_provider


def build_ai_provider(
    model_ref: str | None = None,
    *,
    parent_id: UUID | str | None = None,
    session: Session | None = None,
):
    """归一构造 AI provider：统一经 ``resolve_engine`` 解析模型引用。

    - ``model_ref`` 为 None → 回退全局 ``LLM_PROVIDER``（与既有 ``build_provider()`` 行为一致）。
    - ``model_ref`` 为合法 ModelConfig UUID / 内置模型 id → 解析对应引擎，使批改 / 重生成
      与 chat 一样尊重家长 ``ModelConfig`` 与请求级 ``model``。
    """
    engine = resolve_engine(model_ref, parent_id=parent_id, session=session)
    return build_provider(engine=engine)
