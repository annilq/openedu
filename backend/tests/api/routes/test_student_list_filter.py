"""学生列表过滤/搜索（teacher-scale-up ticket 02 后端部分 / ADR-0068 §2.3）。

覆盖：
- 按班级筛选只返回该班学生
- 按姓名/学号模糊搜索可定位单人或少数人
- 不加筛选返回全部

⚠️ 测试库 session 级、整轮收尾才清空，用户名须全文件唯一。
"""

import uuid

from fastapi.testclient import TestClient

from app.db.models import User
from tests.utils.user import auth_headers, login, register_teacher


def _teacher(client: TestClient, username: str) -> str:
    register_teacher(client, username=username, password="pw123456")
    return login(client, username, "pw123456").json()["access_token"]


def _make_student(client: TestClient, token: str, username: str, display_name: str) -> dict:
    r = client.post(
        "/api/v1/students",
        headers=auth_headers(token),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": display_name,
            "grade": 2,
            "role": "student",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def _assign_class(db, student_id: str, class_id: str) -> None:
    stu = db.get(User, uuid.UUID(student_id))
    stu.class_id = uuid.UUID(class_id)
    db.add(stu)
    db.commit()


def test_list_filter_by_class_and_keyword(client: TestClient, db):
    token = _teacher(client, "flt_owner")
    a = client.post("/api/v1/classes", headers=auth_headers(token), json={"name": "一班", "grade": 3}).json()
    b = client.post("/api/v1/classes", headers=auth_headers(token), json={"name": "二班", "grade": 3}).json()
    cid_a, cid_b = a["id"], b["id"]

    sa1 = _make_student(client, token, "4021001", "阿一")
    sa2 = _make_student(client, token, "4021002", "阿二")
    sb1 = _make_student(client, token, "4022001", "贝一")
    su = _make_student(client, token, "4029001", "未分班生")  # 保持未分班
    _assign_class(db, sa1["id"], cid_a)
    _assign_class(db, sa2["id"], cid_a)
    _assign_class(db, sb1["id"], cid_b)

    # 不筛选 → 全部 4 人
    all_r = client.get("/api/v1/students", headers=auth_headers(token)).json()
    assert all_r["count"] == 4

    # 按班级 A 筛选 → 仅 2 人且都在 A
    ra = client.get(f"/api/v1/students?class_id={cid_a}", headers=auth_headers(token)).json()
    assert ra["count"] == 2
    assert all(u["class_id"] == cid_a for u in ra["data"])

    # 按班级 B 筛选 → 仅 1 人
    rb = client.get(f"/api/v1/students?class_id={cid_b}", headers=auth_headers(token)).json()
    assert rb["count"] == 1
    assert rb["data"][0]["username"] == "4022001"

    # 按学号模糊搜索 → 命中单人
    rk = client.get("/api/v1/students?keyword=4021001", headers=auth_headers(token)).json()
    assert rk["count"] == 1
    assert rk["data"][0]["username"] == "4021001"

    # 按姓名模糊搜索 → 命中单人
    rkn = client.get("/api/v1/students?keyword=贝一", headers=auth_headers(token)).json()
    assert rkn["count"] == 1
    assert rkn["data"][0]["username"] == "4022001"

    # 未分班学生不带 class_id，且不随班级筛选泄漏
    assert su["class_id"] is None
    assert all(u["username"] != "4029001" for u in ra["data"] + rb["data"])
