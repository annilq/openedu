"""各学生活跃错题数聚合端点（teacher-scale-up ticket 02 / ADR-0068 §2.3）。

覆盖：返回 {student_id: 活跃错题数}，只数未毕业（graduated_at 为 NULL）的；
已毕业的不计入；无错题的学生不出现。结果按当前教师归属范围聚合。
"""

from datetime import datetime, timezone
from uuid import UUID

from fastapi.testclient import TestClient
from sqlmodel import Session

from app.db.models import Question, WrongQuestion
from tests.utils.user import auth_headers, login, register_teacher


def _teacher(client: TestClient, username: str) -> tuple[str, str]:
    register_teacher(client, username=username, password="pw123456")
    token = login(client, username, "pw123456").json()["access_token"]
    me = client.get("/api/v1/auth/me", headers=auth_headers(token)).json()
    return token, me["id"]


def _make_student(client: TestClient, token: str, username: str) -> str:
    r = client.post(
        "/api/v1/students",
        headers=auth_headers(token),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": username,
            "grade": 2,
            "role": "student",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _seed(db: Session, *, teacher_id: str, student_id: str, active: int, graduated: int) -> None:
    teacher_uid = UUID(teacher_id)
    student_uid = UUID(student_id)
    qs = []
    for _ in range(active + graduated):
        q = Question(
            teacher_id=teacher_uid,
            subject="数学",
            grade=2,
            knowledge_point="加法",
            qtype="calc",
            stem="1+1=?",
        )
        db.add(q)
        qs.append(q)
    db.commit()
    for q in qs:
        db.refresh(q)
    for i, q in enumerate(qs):
        wq = WrongQuestion(student_id=student_uid, question_id=q.id)
        if i >= active:  # 后面的标记为已毕业
            wq.graduated_at = datetime.now(timezone.utc)
        db.add(wq)
    db.commit()


def test_wrong_question_counts_active_only(client: TestClient, db: Session):
    token, tid = _teacher(client, "wq_owner")
    sa = _make_student(client, token, "wq_a")
    sb = _make_student(client, token, "wq_b")

    _seed(db, teacher_id=tid, student_id=sa, active=2, graduated=1)
    _seed(db, teacher_id=tid, student_id=sb, active=1, graduated=0)

    r = client.get("/api/v1/students/wrong-question-counts", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    counts = r.json()
    assert counts[str(sa)] == 2  # 已毕业的 1 条不计
    assert counts[str(sb)] == 1


def test_wrong_question_counts_excludes_other_teacher(client: TestClient, db: Session):
    ta, tida = _teacher(client, "wq_ta")
    tb, tidb = _teacher(client, "wq_tb")
    sa = _make_student(client, ta, "wq_ta_kid")
    sb = _make_student(client, tb, "wq_tb_kid")

    _seed(db, teacher_id=tida, student_id=sa, active=3, graduated=0)
    _seed(db, teacher_id=tidb, student_id=sb, active=5, graduated=0)

    # 教师 A 只能看到自己学生的计数
    ra = client.get("/api/v1/students/wrong-question-counts", headers=auth_headers(ta))
    assert ra.status_code == 200
    assert ra.json() == {str(sa): 3}


def test_wrong_question_counts_excludes_orphan(client: TestClient, db: Session):
    """源题目被硬删后留下的孤儿错题，不应计入列表徽标（与详情页 JOIN 口径一致）。

    复现真实 bug：列表显示 7、详情只显示 4，差额 3 条是 question 已删除的孤儿错题。
    """
    token, tid = _teacher(client, "wq_orphan_t")
    s = _make_student(client, token, "wq_orphan_kid")
    sid = UUID(s)

    qs = []
    for _ in range(3):
        q = Question(
            teacher_id=UUID(tid),
            subject="数学",
            grade=2,
            knowledge_point="加法",
            qtype="calc",
            stem="1+1=?",
        )
        db.add(q)
        qs.append(q)
    db.commit()
    for q in qs:
        db.refresh(q)
    for q in qs:
        db.add(WrongQuestion(student_id=sid, question_id=q.id))
    db.commit()

    # 硬删其中 1 道源题，遗留 1 条孤儿错题（FK 无级联清理）
    db.delete(qs[0])
    db.commit()

    r = client.get("/api/v1/students/wrong-question-counts", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    # 孤儿不计，只数剩下 2 条源题仍在的活跃错题
    assert r.json() == {str(sid): 2}
