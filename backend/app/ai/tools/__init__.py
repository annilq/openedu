"""跨 SubAgent 复用的 shared_tool（ADR-0024：shared_tool = 公共文件）。

各 subagent 在 manifest ``tools`` 中声明依赖；runtime 按名解析。
当前提供：
- ``list_tasks``：列出某家长的草稿任务及其题目（悬浮助手「查任务题目」）。
- ``search_knowledge``：知识库检索封装（出题/伴学 RAG 用）。
"""
from __future__ import annotations

from uuid import UUID

from sqlmodel import Session

from app.features.tasks.repository import get_draft_tasks, get_task_questions


def list_tasks(session: Session, *, parent_id: UUID) -> list[dict]:
    """列出家长名下草稿任务 + 每题题目（stem/qtype/answer/knowledge_point）。"""
    tasks = get_draft_tasks(session=session, parent_id=parent_id)
    out: list[dict] = []
    for t in tasks:
        qs = get_task_questions(session=session, task_id=t.id)
        subject = ""
        if t.specs:
            for sp in t.specs:
                if isinstance(sp, dict) and sp.get("subject"):
                    subject = sp["subject"]
                    break
        out.append(
            {
                "task_id": str(t.id),
                "title": t.title,
                "subject": subject,
                "status": t.status,
                "questions": [
                    {
                        "stem": q.stem,
                        "qtype": q.qtype,
                        "knowledge_point": q.knowledge_point,
                        "options": q.options,
                        "answer": q.answer,
                    }
                    for q in qs
                ],
            }
        )
    return out


def search_knowledge(retriever, *, subject: str, grade: int, knowledge_point: str, query: str):
    """知识库检索封装（无 retriever 时返回空）。"""
    if retriever is None:
        return []
    return retriever.retrieve(
        subject=subject, grade=grade, knowledge_point=knowledge_point, query=query
    )


__all__ = ["list_tasks", "search_knowledge"]
