"""班级实体与 CRUD 端点（teacher-scale-up ticket 01 / ADR-0068）。

覆盖：建班 / 重名查重 409 / 年级越界 422 / 改名 / 删班降级未分班 / 别教师 403 / student_count。
"""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.db.models import Class, User
from tests.utils.user import auth_headers, login, register_teacher


def _teacher(client: TestClient, username: str) -> tuple[str, uuid.UUID]:
    register_teacher(client, username=username, password="pw123456")
    token = login(client, username, "pw123456").json()["access_token"]
    # teacher_id 从自建班级响应里拿；这里用独立查询取 id。
    me = client.get("/api/v1/auth/me", headers=auth_headers(token)).json()
    return token, uuid.UUID(me["id"])


def test_create_and_list_class(client: TestClient):
    token, _ = _teacher(client, "c_teacher1")
    h = auth_headers(token)
    r = client.post("/api/v1/classes", json={"name": "三年级1班", "grade": 3}, headers=h)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["name"] == "三年级1班" and body["grade"] == 3
    assert body["student_count"] == 0

    lst = client.get("/api/v1/classes", headers=h).json()
    assert len(lst) == 1 and lst[0]["id"] == body["id"]


def test_duplicate_name_rejected(client: TestClient):
    token, _ = _teacher(client, "c_teacher2")
    h = auth_headers(token)
    payload = {"name": "重复班", "grade": 2}
    assert client.post("/api/v1/classes", json=payload, headers=h).status_code == 201
    # 同名再建 → 显式查重拒绝（不依赖 DB 约束）。
    r2 = client.post("/api/v1/classes", json=payload, headers=h)
    assert r2.status_code == 409, r2.text


def test_grade_out_of_range_rejected(client: TestClient):
    token, _ = _teacher(client, "c_teacher3")
    h = auth_headers(token)
    r = client.post("/api/v1/classes", json={"name": "越界班", "grade": 12}, headers=h)
    assert r.status_code == 422, r.text


def test_rename_class(client: TestClient):
    token, _ = _teacher(client, "c_teacher4")
    h = auth_headers(token)
    cid = client.post(
        "/api/v1/classes", json={"name": "旧名班", "grade": 1}, headers=h
    ).json()["id"]
    r = client.patch(
        f"/api/v1/classes/{cid}", json={"name": "新名班", "grade": 4}, headers=h
    )
    assert r.status_code == 200, r.text
    assert r.json()["name"] == "新名班" and r.json()["grade"] == 4


def test_delete_class_unassigns_students(client: TestClient, db: Session):
    token, tid = _teacher(client, "c_teacher5")
    h = auth_headers(token)
    cid = client.post(
        "/api/v1/classes", json={"name": "删前班", "grade": 5}, headers=h
    ).json()["id"]

    # 造一个已分班学生（直写库，避开后续 ticket 的派发逻辑）。
    stu = User(
        username="c_stu_del@x",
        hashed_password="x",
        display_name="学生",
        role="student",
        teacher_id=tid,
        class_id=uuid.UUID(cid),
    )
    db.add(stu)
    db.commit()
    db.refresh(stu)

    # 删班：学生 class_id 置空，但账号与行仍在。
    d = client.delete(f"/api/v1/classes/{cid}", headers=h)
    assert d.status_code == 200, d.text
    db.expire_all()
    remaining = db.exec(select(User).where(User.id == stu.id)).first()
    assert remaining is not None
    assert remaining.class_id is None
    # 班级已不存在
    assert db.get(Class, uuid.UUID(cid)) is None


def test_other_teacher_forbidden(client: TestClient):
    t1, _ = _teacher(client, "c_owner")
    t2, _ = _teacher(client, "c_intruder")
    h1 = auth_headers(t1)
    cid = client.post(
        "/api/v1/classes", json={"name": "私有班", "grade": 6}, headers=h1
    ).json()["id"]
    h2 = auth_headers(t2)
    # 别教师改 / 删 → 403（归一则一源，越权伪装成不存在也要 403）。
    assert (
        client.patch(f"/api/v1/classes/{cid}", json={"name": "x"}, headers=h2).status_code
        == 403
    )
    assert client.delete(f"/api/v1/classes/{cid}", headers=h2).status_code == 403
    # 别教师的列表看不到该班。
    others = client.get("/api/v1/classes", headers=h2).json()
    assert all(c["id"] != cid for c in others)
