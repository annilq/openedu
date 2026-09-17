"""任务来源与错题来源的 service 接缝测试。

HTTP 接缝（``test_export.py``）已证明「请求进来、PDF 出去、越权被拒」；
这里断言两种来源**在装配层**的形状——任务分节与快照、错题的毕业/到期过滤，
这些在 PDF 二进制上看不见。
"""
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlmodel import Session, select

from app.core.errors import AppErrorException
from app.db.models import Question, Task, TaskQuestion, User, WrongQuestion
from app.features.export import service as export_service
from app.features.export.schemas import ExportSheetReq
from tests.utils.user import auth_headers, register_parent


def _register_parent(client, db: Session) -> tuple[User, str]:
    username = f"exp_{uuid.uuid4().hex[:8]}"
    assert register_parent(client, username=username).status_code == 200
    row = db.exec(select(User).where(User.username == username)).first()
    assert row is not None
    token = client.post(
        "/api/v1/auth/login", json={"username": username, "password": "pw123456"}
    ).json()["access_token"]
    return row, token


def _create_child(client, token: str, db: Session) -> User:
    username = f"kid_{uuid.uuid4().hex[:8]}"
    r = client.post(
        "/api/v1/children",
        headers=auth_headers(token),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": "导出测试娃",
            "grade": 2,
            "role": "child",
        },
    )
    assert r.status_code == 201, r.text
    row = db.exec(select(User).where(User.username == username)).first()
    assert row is not None
    return row


def _make_question(db: Session, *, parent_id, stem: str, subject: str = "数学") -> Question:
    q = Question(
        parent_id=parent_id,
        subject=subject,
        grade=2,
        knowledge_point="加法",
        qtype="calc",
        stem=stem,
        options=None,
        answer="answer-should-not-appear",
        explanation="explanation-should-not-appear",
    )
    db.add(q)
    db.commit()
    db.refresh(q)
    return q


def _make_task(db: Session, *, parent_id, title: str, questions: list[Question]) -> Task:
    task = Task(parent_id=parent_id, title=title, status="assigned")
    db.add(task)
    db.commit()
    db.refresh(task)
    for q in questions:
        # 模拟派发快照：TaskQuestion 深拷贝题面字段（与 from-generated 的落库一致）
        db.add(
            TaskQuestion(
                task_id=task.id,
                question_id=q.id,
                subject=q.subject,
                grade=q.grade,
                knowledge_point=q.knowledge_point,
                qtype=q.qtype,
                stem=q.stem,
                options=q.options,
                answer=q.answer,
                explanation=q.explanation,
            )
        )
    db.commit()
    return task


def test_task_source_groups_by_task_and_uses_snapshot(client, db):
    parent, _ = _register_parent(client, db)
    q1 = _make_question(db, parent_id=parent.id, stem="任务一题面")
    q2 = _make_question(db, parent_id=parent.id, stem="任务二题面")
    task = _make_task(db, parent_id=parent.id, title="周末练习", questions=[q1, q2])
    # 源题事后被编辑：印的是快照，不该跟着变
    q1.stem = "源题已被改成另一个样子"
    db.add(q1)
    db.commit()

    document = export_service.build_document(
        session=db,
        parent_id=parent.id,
        req=ExportSheetReq(source="task", ids=[task.id]),
    )
    assert document.title == "周末练习"
    assert [s.heading for s in document.sections] == ["周末练习"]
    assert [q.stem for q in document.sections[0].questions] == ["任务一题面", "任务二题面"]


def test_task_source_rejects_foreign_task(client, db):
    parent, _ = _register_parent(client, db)
    other, _ = _register_parent(client, db)
    q = _make_question(db, parent_id=other.id, stem="别人的")
    task = _make_task(db, parent_id=other.id, title="别人的任务", questions=[q])
    with pytest.raises(AppErrorException) as exc:
        export_service.build_document(
            session=db,
            parent_id=parent.id,
            req=ExportSheetReq(source="task", ids=[task.id]),
        )
    assert exc.value.status_code == 403


def test_wrong_book_skips_graduated_and_filters_due(client, db):
    parent, ptoken = _register_parent(client, db)
    child = _create_child(client, ptoken, db)

    due = _make_question(db, parent_id=parent.id, stem="今天到期")
    future = _make_question(db, parent_id=parent.id, stem="明天才到期")
    graduated = _make_question(db, parent_id=parent.id, stem="已经毕业")
    now = datetime.now(UTC)
    rows = [
        WrongQuestion(
            child_id=child.id,
            question_id=due.id,
            due_at=now - timedelta(minutes=5),
        ),
        WrongQuestion(
            child_id=child.id,
            question_id=future.id,
            due_at=now + timedelta(days=1),
        ),
        WrongQuestion(
            child_id=child.id,
            question_id=graduated.id,
            due_at=now - timedelta(days=1),
            graduated_at=now,
        ),
    ]
    for row in rows:
        db.add(row)
    db.commit()

    all_doc = export_service.build_document(
        session=db,
        parent_id=parent.id,
        req=ExportSheetReq(source="wrong_book", child_id=child.id),
    )
    stems = [q.stem for s in all_doc.sections for q in s.questions]
    assert "已经毕业" not in stems
    assert set(stems) == {"今天到期", "明天才到期"}

    due_doc = export_service.build_document(
        session=db,
        parent_id=parent.id,
        req=ExportSheetReq(source="wrong_book", child_id=child.id, due_only=True),
    )
    due_stems = [q.stem for s in due_doc.sections for q in s.questions]
    assert due_stems == ["今天到期"]


def test_wrong_book_rejects_foreign_child(client, db):
    parent, _ = _register_parent(client, db)
    with pytest.raises(AppErrorException) as exc:
        export_service.build_document(
            session=db,
            parent_id=parent.id,
            req=ExportSheetReq(source="wrong_book", child_id=uuid.uuid4()),
        )
    assert exc.value.status_code == 403
