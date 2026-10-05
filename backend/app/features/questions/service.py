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

from app.features.materials.scene_fusion import scene_spec_for_read
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
    since_days: int | None = None,
    limit: int | None = None,
) -> list[dict[str, Any]]:
    """家长题库浏览（owner 隔离），投影为助手卡片友好的结构化字典。

    **交互讲解走「快照优先 + 实时回退」**（ADR-0061 §M，与 tasks/review 同一口径）：
    出题时算好的 ``Question.scene_spec`` 就是这道题的讲解实例（贴合本题图形/角度）；
    老数据没有快照时回退实时解析（按知识点 + 学期找模板），否则**题库里存的旧题
    永远出不了图**——快照只在出题那一刻生成，而模板往往是之后才配的。
    两者都无 → ``None``，前端不显示图形区（不报错、不占位）。
    """
    page_size = min(limit, _BANK_QUERY_LIMIT) if limit else _BANK_QUERY_LIMIT
    items, _total, usage = _repo_list(
        session=session,
        parent_id=parent_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        qtype=qtype,
        keyword=keyword,
        since_days=since_days,
        page=1,
        page_size=page_size,
    )
    # 同一页里同一 (年级, 学科, 学期, 知识点) 的题共用一份模板解析结果 —— 避免
    # 每题各查一次（同页通常有几十道同知识点的题）。
    scene_cache: dict[tuple, dict | None] = {}
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
            # 学期维度（ADR-0061 §J）：详情页要展示「这题属于哪个学期」——它同时
            # 决定了讲解匹配哪份知识点模板（同学期优先、整学年兜底）。
            "semester": q.semester or "",
            # 交互讲解（ADR-0061 §U）：与题库 REST 端点共用一个函数
            # （``scene_spec_for_read``），避免两条读路径各写一份而漂移。
            "scene_spec": scene_spec_for_read(
                session,
                snapshot=q.scene_spec,
                parent_id=q.parent_id,
                subject=q.subject,
                grade=q.grade,
                knowledge_point=q.knowledge_point,
                semester=q.semester,
                stem=q.stem,
                options=q.options,
                cache=scene_cache,
            ),
        }
        for q in items
    ]
