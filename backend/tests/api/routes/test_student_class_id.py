"""班级归属校验（ADR-0086 后端小扩展 / ticket 05）。

覆盖验收点：
- `POST /students` 带 `class_id` 且属于当前教师 → 该生 `class_id` 落库，且 `GET /students?class_id=` 能查到。
- `POST /students` 带**他人** `class_id` → 403（整体失败，不产生归属错误的账号）。
- `POST /students/import` 带 `class_id` 且属于当前教师 → 导入学生归入本班，且能登录。
- `POST /students/import` 带**他人** `class_id` → 403（整体失败，不部分成功）。

⚠️ 测试库 `db` 是 session 级、仅在整轮收尾清空，故各测试教师用户名必须全文件唯一。
"""

import io

from fastapi.testclient import TestClient
from openpyxl import Workbook

from app.core.config import settings
from tests.utils.user import auth_headers, login, register_teacher

XLSX_CT = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def _teacher(client: TestClient, username: str) -> str:
    register_teacher(client, username=username, password="pw123456")
    return login(client, username, "pw123456").json()["access_token"]


def _create_class(client: TestClient, token: str, name: str, grade: int) -> str:
    r = client.post(
        "/api/v1/classes",
        headers=auth_headers(token),
        json={"name": name, "grade": grade},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _build_xlsx(rows: list[list]) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.append(["姓名", "学号"])
    for row in rows:
        ws.append(row)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def test_create_student_with_owned_class_id(client: TestClient):
    token = _teacher(client, "cid_owner")
    class_id = _create_class(client, token, "三(1)班", 3)

    r = client.post(
        "/api/v1/students",
        headers=auth_headers(token),
        json={
            "username": "3301001",
            "password": "kid123456",
            "display_name": "张三",
            "class_id": class_id,
        },
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["class_id"] == class_id

    # 经筛选端点能查到该生
    lst = client.get(
        "/api/v1/students",
        headers=auth_headers(token),
        params={"class_id": class_id},
    ).json()
    assert lst["count"] == 1
    assert lst["data"][0]["username"] == "3301001"


def test_create_student_with_other_teacher_class_id_forbidden(client: TestClient):
    token_a = _teacher(client, "cid_a")
    token_b = _teacher(client, "cid_b")
    class_id = _create_class(client, token_a, "三(1)班", 3)  # 属于 A

    r = client.post(
        "/api/v1/students",
        headers=auth_headers(token_b),
        json={
            "username": "3302001",
            "password": "kid123456",
            "display_name": "李四",
            "class_id": class_id,  # B 试图塞进 A 的班级
        },
    )
    assert r.status_code == 403, r.text
    assert "班级" in r.json()["message"]


def test_import_with_owned_class_id_assigns(client: TestClient):
    token = _teacher(client, "imp_cid_owner")
    class_id = _create_class(client, token, "四(2)班", 4)
    data = _build_xlsx([["张三", "4401001"], ["李四", "4401002"]])

    r = client.post(
        "/api/v1/students/import",
        headers=auth_headers(token),
        data={"class_id": str(class_id)},
        files={"file": ("roster.xlsx", data, XLSX_CT)},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["created"] == 2
    assert body["skipped"] == 0

    # 导入学生归入本班
    lst = client.get(
        "/api/v1/students",
        headers=auth_headers(token),
        params={"class_id": class_id},
    ).json()
    assert lst["count"] == 2

    # 且能用初始密码登录
    for no in ("4401001", "4401002"):
        login_r = client.post(
            "/api/v1/auth/login",
            json={"username": no, "password": settings.STUDENT_DEFAULT_PASSWORD},
        )
        assert login_r.status_code == 200, login_r.text


def test_import_with_other_teacher_class_id_forbidden(client: TestClient):
    token_a = _teacher(client, "imp_cid_a")
    token_b = _teacher(client, "imp_cid_b")
    class_id = _create_class(client, token_a, "四(2)班", 4)  # 属于 A
    data = _build_xlsx([["王五", "4403001"]])

    r = client.post(
        "/api/v1/students/import",
        headers=auth_headers(token_b),
        data={"class_id": str(class_id)},  # B 越权导入到 A 的班级
        files={"file": ("roster.xlsx", data, XLSX_CT)},
    )
    assert r.status_code == 403, r.text
    assert "班级" in r.json()["message"]

    # 越权失败整体回滚：A 的班级里不应凭空多出学生
    lst = client.get(
        "/api/v1/students",
        headers=auth_headers(token_a),
        params={"class_id": class_id},
    ).json()
    assert lst["count"] == 0
