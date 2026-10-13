"""运行轨迹脱敏 + 破窗留痕（ADR-0088 ticket 03）。

覆盖：
- 默认视图：教师（owner）看自家运行全文；管理员默认脱敏（正文/tool 载荷掩码），
  ``redacted=True``。
- 破窗：仅 admin 可调 ``/reveal``，返回全文并写审计留痕；非 admin（教师）→ 403。
- 审计留痕可查：``/break-glass-logs`` 仅 admin 可见，记录谁/何时/读了哪段/理由。
- 越权（非 owner 教师看他人运行）→ 403（既有护栏，未回归）。
"""
import uuid

from sqlmodel import Session, select

from app.core.db import engine
from app.db.models import BreakGlassAccess, Conversation, Message, Role, User
from tests.utils.user import auth_headers, login, register_teacher


def _make_admin(client, username) -> tuple[str, uuid.UUID]:
    """注册一名教师并就地提升为 admin，返回 (token, user_id)。"""
    r = register_teacher(client, username=username)
    assert r.status_code == 200
    token = r.json()["access_token"]
    with Session(engine) as s:
        u = s.exec(select(User).where(User.username == username)).one()
        u.role = Role.ADMIN
        s.add(u)
        s.commit()
        uid = u.id
    return token, uid


def _seed_run(owner_id: uuid.UUID) -> uuid.UUID:
    """直接落库一条运行 + 一步（含 tool 载荷，模拟学生 PII）。返回 conversation_id。"""
    conv_id = uuid.uuid4()
    with Session(engine) as s:
        s.add(
            Conversation(
                id=conv_id,
                kind="query",
                teacher_id=owner_id,
                title="小明问平行四边形",
                status="done",
            )
        )
        s.add(
            Message(
                conversation_id=conv_id,
                turn=1,
                role="user",
                step="input",
                content="平行四边形是轴对称图形吗？",
                payload={"tool": "quiz_result", "student_id": str(uuid.uuid4()), "answer": "是"},
                model="fake-model",
                input_safe=True,
                output_safe=True,
                blocked=False,
                latency_ms=120,
                usage={"prompt": 10, "completion": 5, "total": 15},
            )
        )
        s.commit()
    return conv_id


def test_teacher_owner_sees_full_text_by_default(client):
    """教师是 owner：默认视图看自家运行全文（redacted=False，原文可见）。"""
    ptoken, _, _ = _setup(client, "rt03_owner", "rt03_kid")
    owner = _owner_id(client, "rt03_owner")
    conv_id = _seed_run(owner)

    r = client.get(
        f"/api/v1/ai/debug/conversations/{conv_id}",
        headers=auth_headers(ptoken),
    )
    assert r.status_code == 200, r.text
    detail = r.json()
    assert detail["messages"][0]["redacted"] is False
    assert detail["messages"][0]["content"] == "平行四边形是轴对称图形吗？"
    assert detail["messages"][0]["payload"] is not None


def test_admin_default_view_is_redacted(client):
    """管理员默认脱敏：正文与 tool 载荷不可见（redacted=True，payload=None）。"""
    ptoken, _, _ = _setup(client, "rt03_owner2", "rt03_kid2")
    owner = _owner_id(client, "rt03_owner2")
    conv_id = _seed_run(owner)
    atoken, _ = _make_admin(client, "rt03_admin")

    r = client.get(
        f"/api/v1/ai/debug/conversations/{conv_id}",
        headers=auth_headers(atoken),
    )
    assert r.status_code == 200, r.text
    msg = r.json()["messages"][0]
    assert msg["redacted"] is True
    assert msg["content"] == "⟨已脱敏⟩"
    assert msg["payload"] is None


def test_reveal_requires_admin(client):
    """破窗仅 admin：教师（非 admin）调 /reveal → 403。"""
    ptoken, _, _ = _setup(client, "rt03_owner3", "rt03_kid3")
    owner = _owner_id(client, "rt03_owner3")
    conv_id = _seed_run(owner)
    atoken, _ = _make_admin(client, "rt03_admin2")

    # 教师调 → 403
    r = client.post(
        f"/api/v1/ai/debug/conversations/{conv_id}/reveal",
        headers=auth_headers(ptoken),
        json={"reason": "排障"},
    )
    assert r.status_code == 403, r.text

    # admin 调 → 200（顺便确认 admin 本身能成功，下一例再查留痕）
    r2 = client.post(
        f"/api/v1/ai/debug/conversations/{conv_id}/reveal",
        headers=auth_headers(atoken),
        json={"reason": "排障"},
    )
    assert r2.status_code == 200, r2.text
    assert r2.json()["messages"][0]["redacted"] is False


def test_reveal_returns_full_text_and_logs_access(client):
    """破窗：admin 调 /reveal 返回全文，并写一条审计留痕（可查）。"""
    atoken, admin_id = _make_admin(client, "rt03_admin3")
    # 用 admin 自己名下的运行（admin 也算 owner 之一，便于 seed）
    conv_id = _seed_run(admin_id)

    r = client.post(
        f"/api/v1/ai/debug/conversations/{conv_id}/reveal",
        headers=auth_headers(atoken),
        json={"reason": "安全审计"},
    )
    assert r.status_code == 200, r.text
    msg = r.json()["messages"][0]
    assert msg["redacted"] is False
    assert msg["content"] == "平行四边形是轴对称图形吗？"
    assert msg["payload"] is not None

    # 留痕可查（按本次 conversation 过滤，避免与同会话其他测试写的留痕混淆）
    logs = client.get(
        "/api/v1/ai/debug/break-glass-logs",
        headers=auth_headers(atoken),
        params={"conversation_id": str(conv_id)},
    )
    assert logs.status_code == 200, logs.text
    rows = logs.json()
    assert len(rows) == 1
    assert rows[0]["actor_id"] == str(admin_id)
    assert rows[0]["conversation_id"] == str(conv_id)
    assert rows[0]["reason"] == "安全审计"

    # DB 直接核验留痕行存在
    with Session(engine) as s:
        db_rows = s.exec(
            select(BreakGlassAccess).where(BreakGlassAccess.conversation_id == conv_id)
        ).all()
        assert len(db_rows) == 1
        assert db_rows[0].actor_id == admin_id
        assert db_rows[0].conversation_id == conv_id


def test_break_glass_logs_requires_admin(client):
    """审计留痕列表仅 admin 可见：教师调 → 403。"""
    ptoken, _, _ = _setup(client, "rt03_owner4", "rt03_kid4")
    atoken, _ = _make_admin(client, "rt03_admin4")

    r = client.get(
        "/api/v1/ai/debug/break-glass-logs",
        headers=auth_headers(ptoken),
    )
    assert r.status_code == 403, r.text

    r2 = client.get(
        "/api/v1/ai/debug/break-glass-logs",
        headers=auth_headers(atoken),
    )
    assert r2.status_code == 200, r2.text


def test_reveal_empty_reason_rejected(client):
    """破窗理由为空 → 422（留痕必须有理由）。"""
    atoken, admin_id = _make_admin(client, "rt03_admin5")
    conv_id = _seed_run(admin_id)
    r = client.post(
        f"/api/v1/ai/debug/conversations/{conv_id}/reveal",
        headers=auth_headers(atoken),
        json={"reason": ""},
    )
    assert r.status_code == 422, r.text


# ───────────────── 归属隔离回归（ADR-0088 §7 / ticket 04）─────────────────


def test_student_cannot_read_run_trace(client):
    """学生无 debug 端点权限：调 /ai/debug/conversations → 403（教师专属）。"""
    _ptoken, _student, ctoken = _setup(client, "rt04_iso_t", "rt04_iso_kid")
    r = client.get("/api/v1/ai/debug/conversations", headers=auth_headers(ctoken))
    assert r.status_code == 403, r.text


def test_teacher_cannot_read_other_teacher_run(client):
    """跨教师越权：教师 B 看教师 A 的运行详情 → 403（归属隔离不因 admin 引入而松动）。"""
    _ptoken_a, _, _ = _setup(client, "rt04_isoA", "rt04_isoA_kid")
    owner_a = _owner_id(client, "rt04_isoA")
    conv_id = _seed_run(owner_a)
    ptoken_b, _, _ = _setup(client, "rt04_isoB", "rt04_isoB_kid")

    r = client.get(
        f"/api/v1/ai/debug/conversations/{conv_id}",
        headers=auth_headers(ptoken_b),
    )
    assert r.status_code == 403, r.text


def test_admin_cross_teacher_read_is_read_only(client):
    """admin 越界只读：可读任意教师运行（200，默认脱敏），且不写业务表。"""
    _ptoken_a, _, _ = _setup(client, "rt04_isoC", "rt04_isoC_kid")
    owner_a = _owner_id(client, "rt04_isoC")
    conv_id = _seed_run(owner_a)
    atoken, admin_id = _make_admin(client, "rt04_admin_iso")

    r = client.get(
        f"/api/v1/ai/debug/conversations/{conv_id}",
        headers=auth_headers(atoken),
    )
    assert r.status_code == 200, r.text
    # admin 默认脱敏：越界能读结构，但看不到未破窗的全文。
    assert r.json()["messages"][0]["redacted"] is True

    # 只读：这次越界读取没有以 admin 名义新建任何业务行（不写 Conversation）。
    with Session(engine) as s:
        own = s.exec(
            select(Conversation).where(Conversation.teacher_id == admin_id)
        ).all()
    assert own == []


# ───────────────────────── helpers ─────────────────────────


def _setup(client, teacher_u, student_u):
    pr = register_teacher(client, username=teacher_u)
    assert pr.status_code == 200
    ptoken = pr.json()["access_token"]
    r = client.post(
        "/api/v1/students",
        headers=auth_headers(ptoken),
        json={
            "username": student_u,
            "password": "kid123456",
            "display_name": "学生",
            "grade": 3,
            "role": "student",
        },
    )
    assert r.status_code == 201, r.text
    lr = login(client, student_u, "kid123456")
    assert lr.status_code == 200, lr.text
    return ptoken, r.json(), lr.json()["access_token"]


def _owner_id(_client, username) -> uuid.UUID:
    with Session(engine) as s:
        u = s.exec(select(User).where(User.username == username)).one()
        return u.id
