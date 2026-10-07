"""作业派发关系与批量派发（teacher-scale-up ticket 08 / ADR-0069）。

覆盖验收点：
- 整班派发：班 N 人 → 派发对象恰好 N 条，任务列表仍是 1 条
- 班级 + 显式学生交集去重：重叠学生只出现一次
- 两个列表都空 → 422
- 全员完成后任务整体转已完成；只完成一半时任务仍是已派发
- 取消部分 / 取消全部派发后状态正确回退
- 派发在单请求内原子：含越权学生则整体拒绝、零写入
- 迁移重复执行不产生重复关系（幂等）
- 作答 / 打卡 / 错题等下游链路不需要改（它们已自带 student_id）
"""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.core.db import engine
from app.db.models import Task, TaskAssignment, User
from tests.utils.user import auth_headers, login, register_teacher


def _teacher(client: TestClient, username: str) -> tuple[str, uuid.UUID]:
    register_teacher(client, username=username, password="pw123456")
    token = login(client, username, "pw123456").json()["access_token"]
    me = client.get("/api/v1/auth/me", headers=auth_headers(token)).json()
    return token, uuid.UUID(me["id"])


def _create_class(client: TestClient, token: str, name: str, grade: int = 3) -> uuid.UUID:
    r = client.post(
        "/api/v1/classes", json={"name": name, "grade": grade}, headers=auth_headers(token)
    )
    assert r.status_code == 201, r.text
    return uuid.UUID(r.json()["id"])


def _create_student(client: TestClient, token: str, username: str) -> dict:
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


def _set_class(db: Session, student_id: uuid.UUID, class_id: uuid.UUID) -> None:
    stu = db.get(User, student_id)
    assert stu is not None
    stu.class_id = class_id
    db.add(stu)
    db.commit()


def _ready_task(db: Session, teacher_id: uuid.UUID) -> Task:
    task = Task(title="批量派发测试", teacher_id=teacher_id, status="ready")
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


def _count_assignments(db: Session, task_id: uuid.UUID) -> int:
    return len(
        db.exec(select(TaskAssignment).where(TaskAssignment.task_id == task_id)).all()
    )


def _login_student(client: TestClient, username: str) -> str:
    return login(client, username, "kid123456").json()["access_token"]


def test_bulk_assign_whole_class(client: TestClient, db: Session):
    """整班派发：班 N 人 → 派发对象恰好 N 条，任务列表仍是 1 条。"""
    token, tid = _teacher(client, "ta1_teacher")
    cid = _create_class(client, token, "三1班")
    sids = []
    for i in range(3):
        s = _create_student(client, token, f"ta1_kid{i}")
        _set_class(db, uuid.UUID(s["id"]), cid)
        sids.append(uuid.UUID(s["id"]))

    task = _ready_task(db, tid)
    r = client.post(
        f"/api/v1/tasks/{task.id}/assign-bulk",
        headers=auth_headers(token),
        json={"class_ids": [str(cid)], "student_ids": []},
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "assigned"

    # 派发对象恰好 3 条
    assert _count_assignments(db, task.id) == 3
    # 任务列表仍是 1 条（不随学生数膨胀）
    lst = client.get("/api/v1/tasks", headers=auth_headers(token)).json()
    assert len(lst["items"]) == 1


def test_bulk_assign_class_and_explicit_dedup(client: TestClient, db: Session):
    """班级 + 显式学生交集去重：重叠学生只出现一次。"""
    token, tid = _teacher(client, "ta2_teacher")
    cid = _create_class(client, token, "三2班")
    class_stu = []
    for i in range(3):
        s = _create_student(client, token, f"ta2_kid{i}")
        _set_class(db, uuid.UUID(s["id"]), cid)
        class_stu.append(uuid.UUID(s["id"]))
    # 班外独立学生 e1
    e1 = _create_student(client, token, "ta2_kid_ext")
    # 显式列表里再放一个已在班里的 a0，制造重叠
    explicit = [str(class_stu[0]), str(uuid.UUID(e1["id"]))]

    task = _ready_task(db, tid)
    r = client.post(
        f"/api/v1/tasks/{task.id}/assign-bulk",
        headers=auth_headers(token),
        json={"class_ids": [str(cid)], "student_ids": explicit},
    )
    assert r.status_code == 200, r.text
    # 目标集合 = {a0,a1,a2,e1} = 4，而非 5（a0 不重复）
    assert _count_assignments(db, task.id) == 4


def test_bulk_assign_empty_lists_rejected(client: TestClient, db: Session):
    """两个列表都空 → 422。"""
    token, tid = _teacher(client, "ta3_teacher")
    task = _ready_task(db, tid)
    r = client.post(
        f"/api/v1/tasks/{task.id}/assign-bulk",
        headers=auth_headers(token),
        json={"class_ids": [], "student_ids": []},
    )
    assert r.status_code == 422, r.text
    # 不写任何派发关系
    assert _count_assignments(db, task.id) == 0


def test_bulk_assign_forbidden_student_atomic(client: TestClient, db: Session):
    """含越权学生 → 整体拒绝（403），且本班合法学生也零写入（原子）。"""
    t1, tid1 = _teacher(client, "ta4_owner")
    t2, _ = _teacher(client, "ta4_intruder")
    cid = _create_class(client, t1, "四1班")
    own_stu = []
    for i in range(2):
        s = _create_student(client, t1, f"ta4_kid{i}")
        _set_class(db, uuid.UUID(s["id"]), cid)
        own_stu.append(uuid.UUID(s["id"]))
    # 别教师的学生
    foreign = _create_student(client, t2, "ta4_foreign")

    task = _ready_task(db, tid1)
    r = client.post(
        f"/api/v1/tasks/{task.id}/assign-bulk",
        headers=auth_headers(t1),
        json={
            "class_ids": [str(cid)],
            "student_ids": [str(uuid.UUID(foreign["id"]))],
        },
    )
    assert r.status_code == 403, r.text
    # 原子：合法班级学生也未被写入（部分失败整体回滚）
    assert _count_assignments(db, task.id) == 0


def test_full_checkin_transitions_to_done(client: TestClient, db: Session):
    """全员完成后任务整体转已完成。"""
    token, tid = _teacher(client, "ta5_teacher")
    cid = _create_class(client, token, "五1班")
    students = []
    for i in range(2):
        s = _create_student(client, token, f"ta5_kid{i}")
        _set_class(db, uuid.UUID(s["id"]), cid)
        students.append(s)

    task = _ready_task(db, tid)
    r = client.post(
        f"/api/v1/tasks/{task.id}/assign-bulk",
        headers=auth_headers(token),
        json={"class_ids": [str(cid)], "student_ids": []},
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "assigned"

    # 两名学生都打卡
    for stu in students:
        ctok = _login_student(client, stu["username"])
        c = client.post(
            f"/api/v1/tasks/{task.id}/checkin", headers=auth_headers(ctok)
        )
        assert c.status_code == 200, c.text

    db.expire_all()
    assert db.get(Task, task.id).status == "done"


def test_partial_checkin_stays_assigned_and_remaining_can_checkin(
    client: TestClient, db: Session
):
    """只完成一半时任务仍是已派发，且未完成的那个学生仍能作答/打卡。"""
    token, tid = _teacher(client, "ta6_teacher")
    cid = _create_class(client, token, "六1班")
    students = []
    for i in range(3):
        s = _create_student(client, token, f"ta6_kid{i}")
        _set_class(db, uuid.UUID(s["id"]), cid)
        students.append(s)

    task = _ready_task(db, tid)
    r = client.post(
        f"/api/v1/tasks/{task.id}/assign-bulk",
        headers=auth_headers(token),
        json={"class_ids": [str(cid)], "student_ids": []},
    )
    assert r.status_code == 200, r.text

    # 只让前两人打卡
    for stu in students[:2]:
        ctok = _login_student(client, stu["username"])
        c = client.post(
            f"/api/v1/tasks/{task.id}/checkin", headers=auth_headers(ctok)
        )
        assert c.status_code == 200, c.text

    db.expire_all()
    assert db.get(Task, task.id).status == "assigned"

    # 剩下的第三名仍能打卡 → 整体转 done（下游作答/打卡链路无需改动）
    ctok = _login_student(client, students[2]["username"])
    c = client.post(f"/api/v1/tasks/{task.id}/checkin", headers=auth_headers(ctok))
    assert c.status_code == 200, c.text
    db.expire_all()
    assert db.get(Task, task.id).status == "done"


def test_cancel_partial_then_full(client: TestClient, db: Session):
    """取消部分派发保持已派发；取消全部回退待派发（ready）。"""
    token, tid = _teacher(client, "ta7_teacher")
    cid = _create_class(client, token, "七1班")
    students = []
    for i in range(3):
        s = _create_student(client, token, f"ta7_kid{i}")
        _set_class(db, uuid.UUID(s["id"]), cid)
        students.append(uuid.UUID(s["id"]))

    task = _ready_task(db, tid)
    r = client.post(
        f"/api/v1/tasks/{task.id}/assign-bulk",
        headers=auth_headers(token),
        json={"class_ids": [str(cid)], "student_ids": []},
    )
    assert r.status_code == 200, r.text
    assert _count_assignments(db, task.id) == 3

    # 取消一名 → 剩 2，状态仍 assigned
    rc = client.post(
        f"/api/v1/tasks/{task.id}/assignments/cancel",
        headers=auth_headers(token),
        json={"student_ids": [str(students[0])]},
    )
    assert rc.status_code == 200, rc.text
    assert _count_assignments(db, task.id) == 2
    db.expire_all()
    assert db.get(Task, task.id).status == "assigned"

    # 取消全部 → 0，状态回退 ready
    rc2 = client.post(
        f"/api/v1/tasks/{task.id}/assignments/cancel",
        headers=auth_headers(token),
        json={"student_ids": []},
    )
    assert rc2.status_code == 200, rc2.text
    assert _count_assignments(db, task.id) == 0
    db.expire_all()
    assert db.get(Task, task.id).status == "ready"


def test_migration_idempotent(client: TestClient, db: Session):
    """迁移重复执行不产生重复关系（幂等）：旧单列 student_id 回填恰好一条。"""
    token, tid = _teacher(client, "ta8_teacher")
    stu = _create_student(client, token, "ta8_kid")
    sid = uuid.UUID(stu["id"])

    # 造一条 legacy 单列派发的 done 任务
    task = Task(
        title="legacy", teacher_id=tid, student_id=sid, status="done"
    )
    db.add(task)
    db.commit()
    db.refresh(task)

    # 重复执行迁移（与启动期 run_migrations 同源的回填逻辑）
    with engine.begin() as conn:
        from app.core.db import _add_task_assignments

        _add_task_assignments(conn, True)
        _add_task_assignments(conn, True)

    db.expire_all()
    rows = db.exec(
        select(TaskAssignment).where(TaskAssignment.task_id == task.id)
    ).all()
    assert len(rows) == 1
    # done 任务的回填应带 completed_at
    assert rows[0].completed_at is not None
