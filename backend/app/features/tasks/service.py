"""Tasks feature service：**只读**业务逻辑（REST 路由与业务查询工具共用，ADR-0033 决策 13）。

本模块只做「读 + 组装 + 裁剪」，不含草稿生成 / 状态流转等写路径——那些涉及 LLM
调用与多步事务，仍留在 router 与 repository。抽出的唯一目的：``/assistant/chat``
的查询工具与 REST 路由共用同一份聚合口径，杜绝第二份实现漂移。
"""

from __future__ import annotations

from uuid import UUID

from sqlmodel import Session

from app.db.models import Question, Task, TaskQuestion, User, WrongQuestion
from app.features.children.service import require_owned_child
from app.features.tasks.repository import (
    get_child_tasks_today,
    get_progress,
    get_task_questions,
    list_tasks_by_parent,
)
from app.features.tasks.repository import (
    list_wrong_questions as repo_list_wrong_questions,
)
from app.features.tasks.schemas import (
    ProgressResp,
    QuestionResp,
    TaskResp,
    WrongQuestionResp,
)

# ───────────────────────── 序列化（ORM → 响应模型） ─────────────────────────


def question_to_resp(tq: TaskQuestion, *, include_answer: bool) -> QuestionResp:
    """TaskQuestion → QuestionResp；``include_answer=False`` 抹掉答案（娃娃端防作弊）。"""
    return QuestionResp(
        id=tq.id,
        question_id=tq.question_id,
        subject=tq.subject,
        grade=tq.grade,
        stem=tq.stem,
        options=tq.options,
        qtype=tq.qtype,
        knowledge_point=tq.knowledge_point,
        explanation=tq.explanation or "",
        answer=tq.answer if include_answer else None,
    )


def task_to_resp(
    task: Task, questions: list[TaskQuestion], *, include_answer: bool
) -> TaskResp:
    return TaskResp(
        id=task.id,
        title=task.title,
        status=task.status,
        specs=task.specs,
        questions=[question_to_resp(q, include_answer=include_answer) for q in questions],
        child_id=task.child_id,
        created_at=task.created_at,
    )


def wrong_question_to_resp(
    wq: WrongQuestion, q: Question, *, include_answer: bool
) -> WrongQuestionResp:
    return WrongQuestionResp(
        id=wq.id,
        question_id=q.id,
        subject=q.subject,
        grade=q.grade,
        knowledge_point=q.knowledge_point,
        qtype=q.qtype,
        stem=q.stem,
        options=q.options,
        answer=q.answer if include_answer else None,
        explanation=q.explanation or "",
        wrong_count=wq.wrong_count,
        first_wrong_at=wq.first_wrong_at,
        review_stage=wq.review_stage,
        due_at=wq.due_at,
    )


# ───────────────────────── 只读用例 ─────────────────────────


def list_parent_tasks(
    *, session: Session, parent_id: UUID, status: str | None = None
) -> list[TaskResp]:
    """家长任务列表（含答案，供审阅/核查）。"""
    return [
        task_to_resp(
            t,
            get_task_questions(session=session, task_id=t.id),
            include_answer=True,
        )
        for t in list_tasks_by_parent(
            session=session, parent_id=parent_id, status=status
        )
    ]


def list_today_tasks(*, session: Session, child_id: UUID) -> list[TaskResp]:
    """娃娃今日任务（assigned/done；不含答案）。"""
    return [
        task_to_resp(
            t,
            get_task_questions(session=session, task_id=t.id),
            include_answer=False,
        )
        for t in get_child_tasks_today(session=session, child_id=child_id)
    ]


def list_wrong_questions(
    *, session: Session, child_id: UUID, include_answer: bool
) -> list[WrongQuestionResp]:
    """错题本。``include_answer`` 由调用方按角色决定；查询工具恒传 True 后交
    ``project_for_role`` 统一裁剪（ADR-0033 决策 9）。"""
    rows = repo_list_wrong_questions(session=session, child_id=child_id)
    return [
        wrong_question_to_resp(wq, q, include_answer=include_answer) for wq, q in rows
    ]


def child_progress(*, session: Session, child_id: UUID) -> ProgressResp:
    """学习进度（纯读取，不做鉴权）。"""
    total, correct, checkin_days, streak = get_progress(
        session=session, child_id=child_id
    )
    return ProgressResp(
        child_id=child_id,
        total=total,
        correct=correct,
        accuracy=round(correct / total, 2) if total else 0.0,
        streak_days=streak,
        checkin_days=checkin_days,
    )


# ───────────────────────── 家长视角复合用例（鉴权 + 读取） ─────────────────────────


def list_owned_child_wrong_questions(
    *, session: Session, parent: User, child_id: UUID
) -> list[WrongQuestionResp]:
    """家长查某娃娃错题本（含答案/解析供核查）；先校验归属。"""
    require_owned_child(session=session, parent=parent, child_id=child_id)
    return list_wrong_questions(session=session, child_id=child_id, include_answer=True)


def owned_child_progress(*, session: Session, parent: User, child_id: UUID) -> ProgressResp:
    """家长查某娃娃学习进度；先校验归属。"""
    require_owned_child(session=session, parent=parent, child_id=child_id)
    return child_progress(session=session, child_id=child_id)
