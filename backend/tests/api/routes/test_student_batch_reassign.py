"""批量移入/移出班级（teacher-scale-up ticket 03 后端）。

覆盖：
- 批量移入某班级成功，返回实际改动行数；重复移入幂等（updated=0）
- 批量移出班级（class_id=null）成功，归入未分班
- 含越权学生 → 整体 403，且**已在校验前**的学生不被部分提交（单事务回滚）
- 指定越权班级 → 整体 403

⚠️ 测试库 session 级、整轮收尾才清空，用户名/学号须全文件唯一。
"""

import uuid

from fastapi.testclient import TestClient

from app.db.models import User
from tests.utils.user import auth_headers, login, register_teacher


def _teacher(client: TestClient, username: str) -> str:
    register_teacher(client, username=username, password="pw123456")
    return login(client, username, "pw123456").json()["access_token"]


def _make_student(client: TestClient, token: str, username: str, name: str) -> dict:
    r = client.post(
        "/api/v1/students",
        headers=auth_headers(token),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": name,
            "grade": 2,
            "role": "student",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def test_batch_move_into_class_and_idempotent(client: TestClient, db):
    token = _teacher(client, "bra_owner")
    cls = client.post(
        "/api/v1/classes", headers=auth_headers(token), json={"name": "三班", "grade": 3}
    ).json()
    cid = cls["id"]

    s1 = _make_student(client, token, "5031001", "甲")
    s2 = _make_student(client, token, "5031002", "乙")

    # 首次移入 → 2 人改动
    r = client.post(
        "/api/v1/students/batch-reassign",
        headers=auth_headers(token),
        json={"class_id": cid, "student_ids": [s1["id"], s2["id"]]},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["updated"] == 2
    assert body["class_id"] == cid

    # 列表应只返回该班 2 人
    flt = client.get(f"/api/v1/students?class_id={cid}", headers=auth_headers(token)).json()
    assert flt["count"] == 2

    # 重复移入 → 幂等，updated=0
    r2 = client.post(
        "/api/v1/students/batch-reassign",
        headers=auth_headers(token),
        json={"class_id": cid, "student_ids": [s1["id"], s2["id"]]},
    )
    assert r2.status_code == 200
    assert r2.json()["updated"] == 0


def test_batch_move_out_to_unclassed(client: TestClient, db):
    token = _teacher(client, "bra_owner2")
    cls = client.post(
        "/api/v1/classes", headers=auth_headers(token), json={"name": "四班", "grade": 3}
    ).json()
    cid = cls["id"]
    s1 = _make_student(client, token, "5041001", "丙")
    s2 = _make_student(client, token, "5041002", "丁")
    client.post(
        "/api/v1/students/batch-reassign",
        headers=auth_headers(token),
        json={"class_id": cid, "student_ids": [s1["id"], s2["id"]]},
    )

    # 移出 → class_id 置空，归入未分班
    r = client.post(
        "/api/v1/students/batch-reassign",
        headers=auth_headers(token),
        json={"class_id": None, "student_ids": [s1["id"], s2["id"]]},
    )
    assert r.status_code == 200, r.text
    assert r.json()["updated"] == 2

    flt = client.get(f"/api/v1/students?class_id={cid}", headers=auth_headers(token)).json()
    assert flt["count"] == 0


def test_rejects_unowned_student_atomic(client: TestClient, db):
    t_a = _teacher(client, "bra_a")
    t_b = _teacher(client, "bra_b")
    # A 的学生
    sa = _make_student(client, t_a, "5051001", "A生")
    # B 先把自己一个学生移入某班（确保 B 有合法班级用于后续试探）
    cls_b = client.post(
        "/api/v1/classes", headers=auth_headers(t_b), json={"name": "B班", "grade": 3}
    ).json()

    # B 试图把 A 的学生塞进自己的班级 → 越权 403
    r = client.post(
        "/api/v1/students/batch-reassign",
        headers=auth_headers(t_b),
        json={"class_id": cls_b["id"], "student_ids": [sa["id"]]},
    )
    assert r.status_code == 403, r.text

    # 关键：A 的学生 class_id 不应被改动（单事务整体回滚，无部分提交）
    refetch = db.get(User, uuid.UUID(sa["id"]))
    assert refetch.class_id is None


def test_rejects_unowned_class(client: TestClient, db):
    t_a = _teacher(client, "bra_a2")
    t_b = _teacher(client, "bra_b2")
    cls_b = client.post(
        "/api/v1/classes", headers=auth_headers(t_b), json={"name": "B班2", "grade": 3}
    ).json()
    sa = _make_student(client, t_a, "5061001", "A生2")

    # A 试图把自家学生移入 B 的班级 → 越权 403
    r = client.post(
        "/api/v1/students/batch-reassign",
        headers=auth_headers(t_a),
        json={"class_id": cls_b["id"], "student_ids": [sa["id"]]},
    )
    assert r.status_code == 403, r.text
    refetch = db.get(User, uuid.UUID(sa["id"]))
    assert refetch.class_id is None
