"""``list_bank_questions`` 的时间过滤（ADR-0050）：since_days 按 created_at 截断。

直接走 repository / service，不接真实模型。借 ``client`` fixture 确保测试库已建表；
SQLite 未开启外键强制，故可用任意 parent_id 直接插 Question 行（仓库只按 parent_id 过滤）。
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlmodel import Session, select

from app.core.db import engine
from app.db.models import Question
from app.features.questions import service as questions_service


def _seed(parent_id: uuid4, created_at: datetime) -> Question:
    q = Question(
        parent_id=parent_id,
        subject="数学",
        grade=4,
        knowledge_point="一元二次方程",
        qtype="calc",
        stem=f"stem {created_at.isoformat()}",
        created_at=created_at,
    )
    with Session(engine) as session:
        session.add(q)
        session.commit()
        session.refresh(q)
    return q


def test_since_days_filters_by_created_at(client):
    parent_id = uuid4()
    now = datetime.now(timezone.utc)
    recent = _seed(parent_id, now - timedelta(hours=2))
    old = _seed(parent_id, now - timedelta(days=10))

    with Session(engine) as session:
        try:
            # 近 3 天：只命中 recent
            items = questions_service.list_bank_questions(
                session=session, parent_id=parent_id, since_days=3
            )
            ids = {i["id"] for i in items}
            assert str(recent.id) in ids
            assert str(old.id) not in ids

            # 叠加学科过滤：时间窗内无「语文」→ 空
            none = questions_service.list_bank_questions(
                session=session, parent_id=parent_id, since_days=3, subject="语文"
            )
            assert none == []

            # since_days=0 / None 不限制时间：两题都在
            all_items = questions_service.list_bank_questions(
                session=session, parent_id=parent_id, since_days=0
            )
            all_ids = {i["id"] for i in all_items}
            assert str(recent.id) in all_ids and str(old.id) in all_ids
        finally:
            for q in session.exec(
                select(Question).where(Question.parent_id == parent_id)
            ).all():
                session.delete(q)
            session.commit()
