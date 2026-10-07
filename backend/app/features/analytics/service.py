"""学情统计聚合（teacher-scale-up ticket 11，ADR-0070）。

三个聚合端点共享同一套「取作用域学生 → 一次 GROUP BY 聚合」逻辑，严禁在端点里循环调取
单学生掌握度（否则大班下 N 次全量扫作答记录）。口径钉死四项（ADR-0070）：

① 年级取**题目的年级**（`Question.grade`），不取学生的年级。
② 学期空值收敛为常量「整学年」，不产生空白分组。
③ 孤儿错题（原题已被硬删，JOIN 不到）归入「未知」并**显式标注数量**（``orphan_count``）。
④ 掌握度跨学生**批量聚合**（本文件），复用 ``app.domain.mastery`` 纯函数保证与单生看板一致。
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import case, func, select

from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned, require_owned_student
from app.db.models import AnswerRecord, Class, Question, WrongQuestion
from app.domain.mastery import compute_mastery_score, mastery_level
from app.features.analytics.schemas import (
    AccuracyGroup,
    AccuracyResp,
    AccuracySourceBreakdown,
    MasteryGroup,
    MasteryResp,
    WrongDistributionGroup,
    WrongDistributionResp,
)
from app.features.auth.repository import list_students

_SCOPES = ("student", "class", "all")
_DIMENSIONS = ("subject", "grade", "semester", "knowledge_point")
_SOURCES = ("practice", "review", "all")


def _resolve_student_ids(
    *,
    session,
    teacher_id: UUID,
    scope: str,
    student_id: UUID | None,
    class_id: UUID | None,
) -> list[UUID]:
    """把三态作用域解析为归属当前教师的学生 id 列表。

    越权（学生/班级不属于当前教师）即抛 403；参数与作用域不匹配抛 422。
    """
    if scope not in _SCOPES:
        raise AppErrorException(
            ErrCode.VALIDATION, "scope 必须是 student / class / all 之一"
        )
    if scope == "student":
        if student_id is None:
            raise AppErrorException(ErrCode.VALIDATION, "scope=student 需要 student_id")
        require_owned_student(
            session=session,
            owner_id=teacher_id,
            student_id=student_id,
            code=ErrCode.FORBIDDEN,
            message="该学生不属于你的账号",
        )
        return [student_id]
    if scope == "class":
        if class_id is None:
            raise AppErrorException(ErrCode.VALIDATION, "scope=class 需要 class_id")
        require_owned(
            session=session,
            owner_id=teacher_id,
            model=Class,
            obj_id=class_id,
            code=ErrCode.FORBIDDEN,
            message="班级不存在或不属于你的账号",
        )
        students = list_students(
            session=session, teacher_id=teacher_id, class_id=class_id
        )
        return [s.id for s in students]
    # all
    students = list_students(session=session, teacher_id=teacher_id)
    return [s.id for s in students]


def _dim_col(dimension: str):
    """映射维度到题目表的列（学期空值收敛为「整学年」）。"""
    if dimension not in _DIMENSIONS:
        raise AppErrorException(
            ErrCode.VALIDATION,
            "dimension 必须是 subject / grade / semester / knowledge_point 之一",
        )
    if dimension == "subject":
        return Question.subject
    if dimension == "grade":
        return Question.grade
    if dimension == "semester":
        # 空字符串与 NULL 都收敛为「整学年」，避免空白分组。
        return case(
            (Question.semester == "", "整学年"),
            (Question.semester.is_(None), "整学年"),
            else_=Question.semester,
        )
    return Question.knowledge_point


def _orphan_wrong_count(session, student_ids: list[UUID]) -> int:
    """孤儿错题数：WrongQuestion LEFT JOIN Question 后 Question.id 为 NULL 的条数。"""
    if not student_ids:
        return 0
    return int(
        session.exec(
            select(func.count())
            .select_from(WrongQuestion)
            .outerjoin(Question, Question.id == WrongQuestion.question_id)
            .where(
                WrongQuestion.student_id.in_(student_ids),
                Question.id.is_(None),
            )
        ).scalar_one()
        or 0
    )


def build_wrong_distribution(
    *, session, student_ids: list[UUID], dimension: str
) -> WrongDistributionResp:
    """按维度聚合错题分布：活跃（未毕业）与已毕业分开计数，孤儿错题单独标注。"""
    if not student_ids:
        return WrongDistributionResp(
            scope="", dimension=dimension, total_active=0,
            total_graduated=0, total=0, groups=[],
            orphan_count=_orphan_wrong_count(session, student_ids),
        )

    col = _dim_col(dimension)
    rows = session.exec(
        select(
            col.label("g"),
            func.sum(
                case((WrongQuestion.graduated_at.is_(None), 1), else_=0)
            ).label("active"),
            func.sum(
                case((WrongQuestion.graduated_at.isnot(None), 1), else_=0)
            ).label("graduated"),
        )
        .select_from(WrongQuestion)
        .join(Question, Question.id == WrongQuestion.question_id)
        .where(WrongQuestion.student_id.in_(student_ids))
        .group_by(col)
    ).all()

    groups: list[WrongDistributionGroup] = []
    total_active = total_graduated = 0
    for g, active, graduated in rows:
        active = int(active or 0)
        graduated = int(graduated or 0)
        total_active += active
        total_graduated += graduated
        groups.append(
            WrongDistributionGroup(
                group=str(g),
                active=active,
                graduated=graduated,
                total=active + graduated,
            )
        )

    return WrongDistributionResp(
        scope="",
        dimension=dimension,
        total_active=total_active,
        total_graduated=total_graduated,
        total=total_active + total_graduated,
        groups=groups,
        orphan_count=_orphan_wrong_count(session, student_ids),
    )


def build_accuracy(
    *, session, student_ids: list[UUID], dimension: str, source: str
) -> AccuracyResp:
    """按维度聚合正确率，练习 / 复习来源分看。"""
    if source not in _SOURCES:
        raise AppErrorException(
            ErrCode.VALIDATION, "source 必须是 practice / review / all 之一"
        )
    if not student_ids:
        return AccuracyResp(
            scope="", dimension=dimension, source=source, groups=[],
            orphan_count=_orphan_accuracy_orphan(session, student_ids),
        )

    col = _dim_col(dimension)
    stmt = (
        select(
            col.label("g"),
            AnswerRecord.source,
            func.count().label("total"),
            func.sum(case((AnswerRecord.correct.is_(True), 1), else_=0)).label("correct"),
        )
        .select_from(AnswerRecord)
        .join(Question, Question.id == AnswerRecord.question_id)
        .where(AnswerRecord.student_id.in_(student_ids))
    )
    if source != "all":
        stmt = stmt.where(AnswerRecord.source == source)
    rows = session.exec(stmt.group_by(col, AnswerRecord.source)).all()

    # 先按 (group, source) 聚合，再拼成 practice/review/overall。
    by_group: dict[str, dict[str, tuple[int, int]]] = {}
    for g, src, total, correct in rows:
        key = str(g)
        by_group.setdefault(key, {"practice": (0, 0), "review": (0, 0)})
        by_group[key][src] = (int(total or 0), int(correct or 0))

    def _bd(t: tuple[int, int]) -> AccuracySourceBreakdown:
        total, correct = t
        return AccuracySourceBreakdown(
            total=total,
            correct=correct,
            accuracy=round(correct / total, 4) if total else 0.0,
        )

    groups: list[AccuracyGroup] = []
    for key, srcs in by_group.items():
        pr = _bd(srcs["practice"])
        rv = _bd(srcs["review"])
        groups.append(
            AccuracyGroup(
                group=key,
                practice=pr,
                review=rv,
                overall=AccuracySourceBreakdown(
                    total=pr.total + rv.total,
                    correct=pr.correct + rv.correct,
                    accuracy=round(
                        (pr.correct + rv.correct) / (pr.total + rv.total), 4
                    )
                    if (pr.total + rv.total)
                    else 0.0,
                ),
            )
        )

    return AccuracyResp(
        scope="",
        dimension=dimension,
        source=source,
        groups=groups,
        orphan_count=_orphan_accuracy_orphan(session, student_ids),
    )


def _orphan_accuracy_orphan(session, student_ids: list[UUID]) -> int:
    """孤儿作答记录数：AnswerRecord LEFT JOIN Question 后 Question.id 为 NULL 的条数。"""
    if not student_ids:
        return 0
    return int(
        session.exec(
            select(func.count())
            .select_from(AnswerRecord)
            .outerjoin(Question, Question.id == AnswerRecord.question_id)
            .where(
                AnswerRecord.student_id.in_(student_ids),
                Question.id.is_(None),
            )
        ).scalar_one()
        or 0
    )


def build_mastery(*, session, student_ids: list[UUID]) -> MasteryResp:
    """批量掌握度：按知识点聚合（跨作用域所有学生），复用 mastery 纯函数。

    活跃（未毕业）错题计入 active_wrong 与 max_review_stage；成绩用累计正确率
    （批量视角下以全量作答代表近窗），避免对每名学生各自滑窗带来的 N 次扫描。
    """
    if not student_ids:
        return MasteryResp(
            scope="", total_knowledge_points=0, mastered_count=0, items=[],
            orphan_count=_orphan_wrong_count(session, student_ids),
        )

    ans_rows = session.exec(
        select(
            Question.knowledge_point,
            Question.subject,
            Question.grade,
            func.count().label("total"),
            func.sum(case((AnswerRecord.correct.is_(True), 1), else_=0)).label("correct"),
        )
        .select_from(AnswerRecord)
        .join(Question, Question.id == AnswerRecord.question_id)
        .where(AnswerRecord.student_id.in_(student_ids))
        .group_by(Question.knowledge_point, Question.subject, Question.grade)
    ).all()

    wq_rows = session.exec(
        select(
            Question.knowledge_point,
            func.count().label("active"),
            func.max(WrongQuestion.review_stage).label("max_stage"),
        )
        .select_from(WrongQuestion)
        .join(Question, Question.id == WrongQuestion.question_id)
        .where(
            WrongQuestion.student_id.in_(student_ids),
            WrongQuestion.graduated_at.is_(None),
        )
        .group_by(Question.knowledge_point)
    ).all()

    agg: dict[str, dict] = {}
    for kp, subject, grade, total, correct in ans_rows:
        agg[kp] = {
            "subject": subject,
            "grade": grade,
            "total": int(total or 0),
            "correct": int(correct or 0),
            "active_wrong": 0,
            "max_review_stage": 0,
        }
    for kp, active, max_stage in wq_rows:
        a = agg.setdefault(
            kp,
            {
                "subject": "",
                "grade": 0,
                "total": 0,
                "correct": 0,
                "active_wrong": 0,
                "max_review_stage": 0,
            },
        )
        a["active_wrong"] = int(active or 0)
        a["max_review_stage"] = int(max_stage or 0)

    items: list[MasteryGroup] = []
    for kp, a in agg.items():
        total = a["total"]
        correct = a["correct"]
        score = compute_mastery_score(
            total_answers=total,
            correct_answers=correct,
            recent_total=total,
            recent_correct=correct,
            active_wrong=a["active_wrong"],
            max_review_stage=a["max_review_stage"],
        )
        items.append(
            MasteryGroup(
                knowledge_point=kp,
                subject=a["subject"],
                grade=a["grade"],
                total_answers=total,
                correct_answers=correct,
                accuracy=round(correct / total, 4) if total else 0.0,
                active_wrong=a["active_wrong"],
                max_review_stage=a["max_review_stage"],
                score=score,
                level=mastery_level(
                    total_answers=total, score=score, active_wrong=a["active_wrong"]
                ),
            )
        )

    mastered = sum(1 for i in items if i.level == "已掌握")
    return MasteryResp(
        scope="",
        total_knowledge_points=len(items),
        mastered_count=mastered,
        items=items,
        orphan_count=_orphan_wrong_count(session, student_ids),
    )
