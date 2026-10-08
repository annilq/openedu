"""ticket 09 端点级验收：答题 / 打卡 / 今日任务 校验改为读派发关系。

后端逻辑（ADR-0069）已于 tasks/service.py 的 ``_answerable_task`` 与
tasks/repository.py 的 ``get_student_tasks_today`` 落地：学生身份下以
``is_student_assigned`` 判定可答/可打卡，未派发即 403；今日任务取「派发关系 ∪ legacy
单列」并集。本文件只补「端点级」验证——逐个派发对象账号真实调答题 / 打卡 / 今日接口，
只改 service 不落端点等于没做。

以直接落库 Task/TaskQuestion/TaskAssignment 做测试前置（这些不是被测对象），被测对象
是三个端点对派发关系的真实响应。
"""

import uuid
from datetime import timedelta

import pytest
from sqlmodel import Session, select

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.db.models.progress import AnswerRecord, Checkin
from app.db.models.question import Question
from app.db.models.task import Task, TaskQuestion
from app.db.models.task_assignment import TaskAssignment
from app.db.models.class_entity import Class
from app.db.models.user import User
from app.features.tasks import service as tasks_service
from tests.utils.fake_provider import FakeLLMProvider
from tests.utils.user import auth_headers


@pytest.fixture
def stub_grader(monkeypatch):
    """answer() 会无条件构造 provider（即使客观题不真调模型），统一用确定性替身。"""
    monkeypatch.setattr(
        tasks_service, "build_ai_provider", lambda *a, **k: FakeLLMProvider()
    )


def _make_teacher(client, username):
    """教师走真实自注册流程（register 端点硬编码 role=teacher）。返回 (id, token)。"""
    client.post(
        "/api/v1/auth/register",
        json={
            "username": username,
            "password": "pw123456",
            "display_name": username,
            "role": "teacher",
        },
    )
    r = client.post(
        "/api/v1/auth/login", json={"username": username, "password": "pw123456"}
    )
    token = r.json()["access_token"]
    me = client.get("/api/v1/auth/me", headers=auth_headers(token)).json()
    return uuid.UUID(me["id"]), token


def _make_student(db: Session, username, teacher_id=None, class_id=None):
    """学生由教师端创建（无自注册），测试里直接落库并签 JWT，返回 (id, token)。

    ``teacher_id``/``class_id`` 可选：批量派发（ticket 18）需学生归属当前教师且/或分班。
    """
    user = User(
        username=username,
        display_name=username,
        role="student",
        hashed_password=get_password_hash("pw123456"),
        teacher_id=teacher_id,
        class_id=class_id,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token(
        user.id, timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    return user.id, token


def _make_class(db: Session, teacher_id: uuid.UUID, name: str, grade: int = 4) -> uuid.UUID:
    """建一个归属教师的班级，返回 class_id。"""
    cls = Class(teacher_id=teacher_id, name=name, grade=grade)
    db.add(cls)
    db.commit()
    db.refresh(cls)
    return cls.id


def _make_ready_task(db: Session, teacher_id: uuid.UUID):
    """建一道 ready 态任务（未派发），返回 (task_id, question_id)。

    批量派发端点要求任务处于 ready/assigned 态，故这里用 ``ready`` 起步。
    """
    q = Question(
        teacher_id=teacher_id,
        subject="数学",
        grade=4,
        knowledge_point="加减",
        qtype="calc",
        stem="1+1=?",
        answer="2",
        explanation="等于2",
    )
    db.add(q)
    db.commit()
    db.refresh(q)

    task = Task(teacher_id=teacher_id, title="随堂测", status="ready", student_id=None)
    db.add(task)
    db.commit()
    db.refresh(task)

    tq = TaskQuestion(
        task_id=task.id,
        question_id=q.id,
        subject="数学",
        grade=4,
        knowledge_point="加减",
        qtype="calc",
        stem="1+1=?",
        answer="2",
        semester="",
    )
    db.add(tq)
    db.commit()
    db.refresh(tq)
    return task.id, tq.id


def _make_task(db: Session, teacher_id: uuid.UUID, assigned: list[uuid.UUID]):
    """建一道已派发任务（无 legacy 单列 student_id），返回 (task_id, question_id)。

    只走派发关系，便于隔离验证「未派发即 403」。
    """
    q = Question(
        teacher_id=teacher_id,
        subject="数学",
        grade=4,
        knowledge_point="加减",
        qtype="calc",
        stem="1+1=?",
        answer="2",
        explanation="等于2",
    )
    db.add(q)
    db.commit()
    db.refresh(q)

    task = Task(teacher_id=teacher_id, title="随堂测", status="assigned", student_id=None)
    db.add(task)
    db.commit()
    db.refresh(task)

    tq = TaskQuestion(
        task_id=task.id,
        question_id=q.id,
        subject="数学",
        grade=4,
        knowledge_point="加减",
        qtype="calc",
        stem="1+1=?",
        answer="2",
        semester="",
    )
    db.add(tq)
    db.commit()
    db.refresh(tq)

    for sid in assigned:
        db.add(TaskAssignment(task_id=task.id, student_id=sid))
    db.commit()
    return task.id, tq.id


def test_unassigned_student_answer_returns_403(client, db, stub_grader):
    teacher_id, _ = _make_teacher(client, "t09_teacher")
    s1, _ = _make_student(db, "t09_s1")
    s2, tok2 = _make_student(db, "t09_s2")

    task_id, q_id = _make_task(db, teacher_id, assigned=[s1])

    # 未派发学生答题 → 403（最易回归项）。
    r = client.post(
        f"/api/v1/tasks/{task_id}/answer",
        headers=auth_headers(tok2),
        json={"question_id": str(q_id), "student_answer": "2"},
    )
    assert r.status_code == 403, r.text

    # 确认确实没落下作答记录（数据没串）。
    recs = db.exec(
        select(AnswerRecord).where(AnswerRecord.student_id == s2)
    ).all()
    assert recs == []


def test_assigned_student_answer_succeeds(client, db, stub_grader):
    teacher_id, _ = _make_teacher(client, "t09b_teacher")
    s1, tok1 = _make_student(db, "t09b_s1")
    _make_student(db, "t09b_s2")

    task_id, q_id = _make_task(db, teacher_id, assigned=[s1])

    r = client.post(
        f"/api/v1/tasks/{task_id}/answer",
        headers=auth_headers(tok1),
        json={"question_id": str(q_id), "student_answer": "2"},
    )
    assert r.status_code == 200, r.text
    assert r.json()["correct"] is True

    recs = db.exec(
        select(AnswerRecord).where(AnswerRecord.student_id == s1)
    ).all()
    assert len(recs) == 1
    assert recs[0].correct is True


def test_checkin_only_recognizes_assignment(client, db, stub_grader):
    teacher_id, _ = _make_teacher(client, "t09c_teacher")
    s1, tok1 = _make_student(db, "t09c_s1")
    s2, tok2 = _make_student(db, "t09c_s2")

    task_id, _ = _make_task(db, teacher_id, assigned=[s1])

    # 被派发学生打卡成功。
    r1 = client.post(
        f"/api/v1/tasks/{task_id}/checkin", headers=auth_headers(tok1)
    )
    assert r1.status_code == 200, r1.text
    assert (
        db.exec(select(Checkin).where(Checkin.student_id == s1)).first() is not None
    )

    # 未派发学生打卡 → 403（只认派发关系）。
    r2 = client.post(
        f"/api/v1/tasks/{task_id}/checkin", headers=auth_headers(tok2)
    )
    assert r2.status_code == 403, r2.text


def test_today_tasks_only_shows_assigned_self(client, db, stub_grader):
    teacher_id, _ = _make_teacher(client, "t09d_teacher")
    s1, tok1 = _make_student(db, "t09d_s1")
    s2, tok2 = _make_student(db, "t09d_s2")

    task_id, _ = _make_task(db, teacher_id, assigned=[s1])

    today1 = client.get("/api/v1/tasks/today", headers=auth_headers(tok1)).json()
    assert any(t["id"] == str(task_id) for t in today1)

    today2 = client.get("/api/v1/tasks/today", headers=auth_headers(tok2)).json()
    assert all(t["id"] != str(task_id) for t in today2)


def test_half_complete_keeps_other_answerable(client, db, stub_grader):
    """只完成一半时，未完成的那个学生仍能作答（ADR-0069 状态语义）。"""
    teacher_id, _ = _make_teacher(client, "t09e_teacher")
    s1, tok1 = _make_student(db, "t09e_s1")
    s2, tok2 = _make_student(db, "t09e_s2")

    task_id, q_id = _make_task(db, teacher_id, assigned=[s1, s2])

    # s1 打卡（完成自己那一份），整体应为 assigned 而非 done。
    client.post(f"/api/v1/tasks/{task_id}/checkin", headers=auth_headers(tok1))
    assert (
        db.exec(select(Task).where(Task.id == task_id)).one().status == "assigned"
    )

    # s2（未完成）仍可答题 → 200。
    r = client.post(
        f"/api/v1/tasks/{task_id}/answer",
        headers=auth_headers(tok2),
        json={"question_id": str(q_id), "student_answer": "2"},
    )
    assert r.status_code == 200, r.text


# ───────────────────────── ticket 18：批量派发端点级验收 ─────────────────────────
# 沿用上面 09 的「逐个派发对象账号真实调答题接口」断言缝：只改 service 不落端点等于没做。


def test_bulk_dispatch_class_and_students_all_answerable(client, db, stub_grader):
    """整班 + 额外学生批量派发后，班级内每个成员与额外学生均可作答（200），非派发对象
    → 403 且未落作答记录（数据没串）。"""
    teacher_id, teacher_tok = _make_teacher(client, "t18_teacher")
    class_id = _make_class(db, teacher_id, "t18_class", 4)
    cs1, tok_cs1 = _make_student(
        db, "t18_cs1", teacher_id=teacher_id, class_id=class_id
    )
    cs2, tok_cs2 = _make_student(
        db, "t18_cs2", teacher_id=teacher_id, class_id=class_id
    )
    extra, tok_extra = _make_student(db, "t18_extra", teacher_id=teacher_id)
    outsider, tok_out = _make_student(db, "t18_out", teacher_id=teacher_id)

    task_id, q_id = _make_ready_task(db, teacher_id)

    # 批量派发：整班（cs1, cs2）+ 一个不在班内的额外学生。
    r = client.post(
        f"/api/v1/tasks/{task_id}/assign-bulk",
        headers=auth_headers(teacher_tok),
        json={"class_ids": [str(class_id)], "student_ids": [str(extra)]},
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "assigned"

    # 班级内成员 + 额外学生 全部可作答。
    for tok in (tok_cs1, tok_cs2, tok_extra):
        ra = client.post(
            f"/api/v1/tasks/{task_id}/answer",
            headers=auth_headers(tok),
            json={"question_id": str(q_id), "student_answer": "2"},
        )
        assert ra.status_code == 200, ra.text
        assert ra.json()["correct"] is True

    # 非派发对象 → 403，且未落下作答记录（数据没串）。
    ro = client.post(
        f"/api/v1/tasks/{task_id}/answer",
        headers=auth_headers(tok_out),
        json={"question_id": str(q_id), "student_answer": "2"},
    )
    assert ro.status_code == 403, ro.text
    recs = db.exec(
        select(AnswerRecord).where(AnswerRecord.student_id == outsider)
    ).all()
    assert recs == []


def test_bulk_dispatch_empty_targets_returns_422(client, db, stub_grader):
    """班级与学生列表同时为空 → 422（BulkAssignReq 契约，ticket 08 验收点）。"""
    teacher_id, teacher_tok = _make_teacher(client, "t18b_teacher")
    task_id, _ = _make_ready_task(db, teacher_id)

    r = client.post(
        f"/api/v1/tasks/{task_id}/assign-bulk",
        headers=auth_headers(teacher_tok),
        json={"class_ids": [], "student_ids": []},
    )
    assert r.status_code == 422, r.text
