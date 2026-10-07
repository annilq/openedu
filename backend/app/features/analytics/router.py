"""学情统计聚合路由（teacher-scale-up ticket 11，ADR-0070）。

三个端点共享「解析三态作用域 → 批量聚合」：错题分布 / 正确率 / 掌握度。路由只做
「接参数 → 解析归属 → 调 service → 填 scope」，聚合与越权校验全部在 service 层。
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Query

from app.core.deps import CurrentTeacher, SessionDep
from app.features.analytics.schemas import (
    AccuracyResp,
    MasteryResp,
    WrongDistributionResp,
)
from app.features.analytics.service import (
    _resolve_student_ids,
    build_accuracy,
    build_mastery,
    build_wrong_distribution,
)

router = APIRouter(prefix="/analytics", tags=["analytics"])


def _student_ids(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    scope: str,
    student_id: UUID | None,
    class_id: UUID | None,
) -> list[UUID]:
    return _resolve_student_ids(
        session=session,
        teacher_id=teacher.id,
        scope=scope,
        student_id=student_id,
        class_id=class_id,
    )


@router.get("/wrong-distribution", response_model=WrongDistributionResp)
def wrong_distribution(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    scope: str = Query(..., description="student | class | all"),
    student_id: UUID | None = Query(default=None),
    class_id: UUID | None = Query(default=None),
    dimension: str = Query(default="knowledge_point"),
) -> WrongDistributionResp:
    """错题分布：按维度（学科/年级/学期/知识点）分组，活跃与已毕业分开计数。

    孤儿错题（原题被硬删）落入 ``orphan_count`` 显式标注，不混入任何分组。
    年级取**题目的年级**；空学期收敛为「整学年」。
    """
    ids = _student_ids(
        session=session, teacher=teacher, scope=scope,
        student_id=student_id, class_id=class_id,
    )
    resp = build_wrong_distribution(session=session, student_ids=ids, dimension=dimension)
    resp.scope = scope
    return resp


@router.get("/accuracy", response_model=AccuracyResp)
def accuracy(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    scope: str = Query(..., description="student | class | all"),
    student_id: UUID | None = Query(default=None),
    class_id: UUID | None = Query(default=None),
    dimension: str = Query(default="knowledge_point"),
    source: str = Query(default="all", description="practice | review | all"),
) -> AccuracyResp:
    """正确率：按维度分组，练习 / 复习两种来源正确率分看（source 可限定单一来源）。"""
    ids = _student_ids(
        session=session, teacher=teacher, scope=scope,
        student_id=student_id, class_id=class_id,
    )
    resp = build_accuracy(
        session=session, student_ids=ids, dimension=dimension, source=source
    )
    resp.scope = scope
    return resp


@router.get("/mastery", response_model=MasteryResp)
def mastery(
    *,
    session: SessionDep,
    teacher: CurrentTeacher,
    scope: str = Query(..., description="student | class | all"),
    student_id: UUID | None = Query(default=None),
    class_id: UUID | None = Query(default=None),
) -> MasteryResp:
    """掌握度：按知识点批量聚合（跨作用域所有学生一次算完，严禁循环单生掌握度）。

    每知识点给出累计作答/正确数、活跃错题数与阶段峰值，score/level 复用 `app.domain.mastery`
    纯函数，与单学生看板口径一致；孤儿错题（原题被删）落入 ``orphan_count``。
    """
    ids = _student_ids(
        session=session, teacher=teacher, scope=scope,
        student_id=student_id, class_id=class_id,
    )
    resp = build_mastery(session=session, student_ids=ids)
    resp.scope = scope
    return resp
