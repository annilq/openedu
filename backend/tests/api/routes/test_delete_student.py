"""删除学生账号与级联清理（teacher-scale-up ticket 04 / ADR-0068）。

覆盖验收点：
- 删学生成功，账号从列表消失
- 响应明确回传清理的作答 / 打卡 / 错题 / 派发关系行数
- 级联清理生效（删后相关行确实消失；单事务原子）
- 别教师的学生不可删（403）
- 删后该学生相关的派发关系一并清理（与 teacher-08 的 taskassignment 表打通）
"""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.db.models import (
    AnswerRecord,
    Checkin,
    Question,
    Task,
    TaskAssignment,
    WrongQuestion,
)
from tests.utils.user import auth_headers, login, register_teacher


def _teacher(client: TestClient, username: str) -> tuple[str, uuid.UUID]:
    register_teacher(client, username=username, password="pw123456")
    token = login(client, username, "pw123456").json()["access_token"]
    me = client.get("/api/v1/auth/me", headers=auth_headers(token)).json()
    return token, uuid.UUID(me["id"])


def _make_student(client: TestClient, token: str, username: str) -> dict:
    r = client.post(
        "/api/v1/students",
        headers=auth_headers(token),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": "学生",
            "grade": 2,
            "role": "student",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def _seed_dependents(
    db: Session,
    *,
    teacher_id: uuid.UUID,
    student_id: uuid.UUID,
    task_id: uuid.UUID,
) -> dict:
    """造作答/打卡/错题/派发关系各若干，返回预期计数。

    错题按 (student_id, question_id) 唯一，故用 3 道不同题各自挂一条错题，
    否则会撞唯一约束（这正是 Why 这条 UNIQUE 的意义：同题只留一条、错多次累加）。
    """
    qs = []
    for i in range(3):
        q = Question(
            teacher_id=teacher_id,
            subject="数学",
            grade=2,
            knowledge_point="加法",
            qtype="calc",
            stem=f"1+{i}=?",
        )
        db.add(q)
        qs.append(q)
    db.commit()
    for q in qs:
        db.refresh(q)

    recs = [
        AnswerRecord(question_id=qs[0].id, student_id=student_id, student_answer="2"),
        AnswerRecord(question_id=qs[1].id, student_id=student_id, student_answer="3"),
    ]
    db.add_all(recs)
    cin = Checkin(student_id=student_id, task_id=task_id)
    db.add(cin)
    wqs = [WrongQuestion(student_id=student_id, question_id=q.id) for q in qs]
    db.add_all(wqs)
    ta = TaskAssignment(task_id=task_id, student_id=student_id)
    db.add(ta)
    db.commit()
    return {
        "answer_records": 2,
        "checkins": 1,
        "wrong_questions": 3,
        "task_assignments": 1,
    }


def _count_rows(db: Session, model, student_id: uuid.UUID) -> int:
    return len(
        db.exec(select(model).where(model.student_id == student_id)).all()
    )


def test_delete_student_removes_from_list_and_returns_counts(client: TestClient, db: Session):
    token, tid = _teacher(client, "d4_owner")
    stu = _make_student(client, token, "d4_kid")
    sid = uuid.UUID(stu["id"])
    task = Task(title="t", teacher_id=tid, status="ready")
    db.add(task)
    db.commit()
    db.refresh(task)

    expected = _seed_dependents(db, teacher_id=tid, student_id=sid, task_id=task.id)

    r = client.delete(
        f"/api/v1/students/{sid}", headers=auth_headers(token)
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["deleted"] is True
    assert body["student_id"] == str(sid)
    assert body["answer_records"] == expected["answer_records"]
    assert body["checkins"] == expected["checkins"]
    assert body["wrong_questions"] == expected["wrong_questions"]
    assert body["task_assignments"] == expected["task_assignments"]

    # 账号从列表消失
    lst = client.get("/api/v1/students", headers=auth_headers(token)).json()
    assert all(u["id"] != str(sid) for u in lst["data"])

    # 级联行确实消失
    db.expire_all()
    assert _count_rows(db, AnswerRecord, sid) == 0
    assert _count_rows(db, Checkin, sid) == 0
    assert _count_rows(db, WrongQuestion, sid) == 0
    assert _count_rows(db, TaskAssignment, sid) == 0


def test_delete_other_teacher_student_forbidden(client: TestClient, db: Session):
    t1, _ = _teacher(client, "d4_t1")
    t2, _ = _teacher(client, "d4_t2")
    stranger = _make_student(client, t2, "d4_kid_other")

    r = client.delete(
        f"/api/v1/students/{stranger['id']}", headers=auth_headers(t1)
    )
    assert r.status_code == 403, r.text
    # 目标学生仍在
    lst = client.get("/api/v1/students", headers=auth_headers(t2)).json()
    assert any(u["id"] == stranger["id"] for u in lst["data"])


def test_delete_clears_task_assignment_relation(client: TestClient, db: Session):
    """删学生时一并清理其派发关系（teacher-08 的 taskassignment 表打通）。"""
    token, tid = _teacher(client, "d4_rel")
    stu = _make_student(client, token, "d4_kid_rel")
    sid = uuid.UUID(stu["id"])
    task = Task(title="t", teacher_id=tid, status="ready")
    db.add(task)
    db.commit()
    db.refresh(task)
    db.add(TaskAssignment(task_id=task.id, student_id=sid))
    db.commit()

    r = client.delete(f"/api/v1/students/{sid}", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    assert r.json()["task_assignments"] == 1
    db.expire_all()
    assert (
        db.exec(
            select(TaskAssignment).where(TaskAssignment.student_id == sid)
        ).first()
        is None
    )
