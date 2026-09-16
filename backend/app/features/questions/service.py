"""Service layer for the questions (bank) feature.

查询工具取数的唯一下游（ADR-0033 决策 13 / 分层不变量 7）：把 repository 行投影成
dump 友好的结构化字典（UUID / datetime → str），并合并每题被任务引用的复用度
``usage_count``。写路径（组卷 / 删除）留在 router + repository；本模块刻意只读，
因为 query 工具的 handler 在 SSE 请求内同步直调 service，不经 ASGI（不变量 6）。
"""
from __future__ import annotations

from typing import Any
from uuid import UUID

from sqlmodel import Session

from app.features.questions.repository import list_bank_questions as _repo_list

# 对话场景上限：取前 N 条，不做无限翻页（仓库分页在此收口为「截断」）。
_BANK_QUERY_LIMIT = 200


def list_bank_questions(
    *,
    session: Session,
    parent_id: UUID,
    subject: str | None = None,
    grade: int | None = None,
    knowledge_point: str | None = None,
    qtype: str | None = None,
    keyword: str | None = None,
    limit: int | None = None,
) -> list[dict[str, Any]]:
    """家长题库浏览（owner 隔离），投影为助手卡片友好的结构化字典。"""
    page_size = min(limit, _BANK_QUERY_LIMIT) if limit else _BANK_QUERY_LIMIT
    items, _total, usage = _repo_list(
        session=session,
        parent_id=parent_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        keyword=keyword,
        page=1,
        page_size=page_size,
    )
    return [
        {
            "id": str(q.id),
            "subject": q.subject,
            "grade": q.grade,
            "knowledge_point": q.knowledge_point,
            "qtype": q.qtype,
            "stem": q.stem,
            "options": q.options,
            "difficulty": q.difficulty,
            "answer": q.answer,
            "explanation": q.explanation,
            "created_at": q.created_at.isoformat() if q.created_at else None,
            "usage_count": usage.get(q.id, 0),
        }
        for q in items
    ]
