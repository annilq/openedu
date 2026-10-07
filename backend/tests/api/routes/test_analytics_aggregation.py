"""学情统计聚合端点（teacher-scale-up ticket 11，ADR-0070）。

覆盖 ADR-0070 钉死的四项口径 + 三态作用域 + 越权隔离 + 大班可接受：
- 四维分组（subject/grade/semester/knowledge_point）各自求和等于总数（防 JOIN 丢/重计数）
- 年级取**题目的年级**（不取学生年级）
- 空学期收敛为「整学年」
- 孤儿错题（原题被硬删）落 ``orphan_count`` 显式标注
- 活跃 / 已毕业错题分开计数
- 练习 / 复习正确率分看
- 跨教师学生不出现在我的统计里

⚠️ 测试库 session 级、整轮收尾才清空，用户名/学号须全文件唯一。
"""

import datetime
import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.db.models import AnswerRecord, Question, User, WrongQuestion
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
            "grade": 3,
            "role": "student",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def _seed_question(
    db: Session, *, teacher_id: uuid.UUID, subject: str, grade: int,
    semester: str, kp: str,
) -> Question:
    q = Question(
        teacher_id=teacher_id, subject=subject, grade=grade,
        knowledge_point=kp, semester=semester, qtype="choice", stem=f"{kp} 题",
    )
    db.add(q)
    db.commit()
    db.refresh(q)
    return q


def _seed_answer(
    db: Session, *, student_id: uuid.UUID, question_id: uuid.UUID,
    correct: bool, source: str,
) -> None:
    db.add(AnswerRecord(
        question_id=question_id, student_id=student_id,
        student_answer="A", correct=correct, score=1.0 if correct else 0.0,
        source=source,
    ))
    db.commit()


def _seed_wrong(
    db: Session, *, student_id: uuid.UUID, question_id: uuid.UUID,
    graduated: bool,
) -> None:
    wq = WrongQuestion(student_id=student_id, question_id=question_id)
    if graduated:
        wq.graduated_at = datetime.datetime.now(datetime.timezone.utc)
    db.add(wq)
    db.commit()


def _group_map(resp: dict) -> dict[str, dict]:
    return {g["group"]: g for g in resp["groups"]}


def test_wrong_distribution_by_knowledge_point_and_active_split(
    client: TestClient, db: Session
):
    token = _teacher(client, "ana_owner")
    t = login(client, "ana_owner", "pw123456").json()["access_token"]
    me = db.exec(
        select(User).where(User.username == "ana_owner")
    ).first()
    stu = _make_student(client, token, "6111001", "甲")
    sid = uuid.UUID(stu["id"])

    q_active = _seed_question(db, teacher_id=me.id, subject="数学", grade=5,
                              semester="上学期", kp="分数加法")
    q_grad = _seed_question(db, teacher_id=me.id, subject="数学", grade=5,
                            semester="上学期", kp="分数减法")
    # (student, question) 唯一：同一题只留一条错题行；活跃/已毕业由 graduated_at 区分。
    _seed_wrong(db, student_id=sid, question_id=q_active.id, graduated=False)
    _seed_wrong(db, student_id=sid, question_id=q_grad.id, graduated=True)

    r = client.get(
        "/api/v1/analytics/wrong-distribution?scope=student"
        f"&student_id={sid}&dimension=knowledge_point",
        headers=auth_headers(t),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["scope"] == "student"
    gm = _group_map(body)
    # 活跃：分数加法 1 条；已毕业：分数减法 1 条。
    assert gm["分数加法"]["active"] == 1 and gm["分数加法"]["graduated"] == 0
    assert gm["分数减法"]["active"] == 0 and gm["分数减法"]["graduated"] == 1
    # 各维分组求和 == total（防重复计数）。
    assert body["total_active"] == 1 and body["total_graduated"] == 1
    assert body["total"] == 2


def test_grade_dimension_takes_question_grade_not_student_grade(
    client: TestClient, db: Session
):
    token = _teacher(client, "ana_grade")
    t = login(client, "ana_grade", "pw123456").json()["access_token"]
    me = db.exec(
        select(User).where(User.username == "ana_grade")
    ).first()
    stu = _make_student(client, token, "6121001", "乙")  # 学生 grade=3
    sid = uuid.UUID(stu["id"])
    q = _seed_question(db, teacher_id=me.id, subject="语文", grade=7,  # 题目 grade=7
                       semester="", kp="古诗")
    _seed_wrong(db, student_id=sid, question_id=q.id, graduated=False)

    r = client.get(
        "/api/v1/analytics/wrong-distribution?scope=student"
        f"&student_id={sid}&dimension=grade",
        headers=auth_headers(t),
    )
    assert r.status_code == 200, r.text
    gm = _group_map(r.json())
    assert "7" in gm, "年级应取题目的年级(7)而非学生的年级(3)"
    assert gm["7"]["active"] == 1


def test_empty_semester_collapses_to_full_year(client: TestClient, db: Session):
    token = _teacher(client, "ana_sem")
    t = login(client, "ana_sem", "pw123456").json()["access_token"]
    me = db.exec(
        select(User).where(User.username == "ana_sem")
    ).first()
    stu = _make_student(client, token, "6131001", "丙")
    sid = uuid.UUID(stu["id"])
    q1 = _seed_question(db, teacher_id=me.id, subject="英", grade=3, semester="", kp="单词")
    q2 = _seed_question(db, teacher_id=me.id, subject="英", grade=3, semester="上学期", kp="阅读")
    _seed_wrong(db, student_id=sid, question_id=q1.id, graduated=False)
    _seed_wrong(db, student_id=sid, question_id=q2.id, graduated=False)

    r = client.get(
        "/api/v1/analytics/wrong-distribution?scope=student"
        f"&student_id={sid}&dimension=semester",
        headers=auth_headers(t),
    )
    assert r.status_code == 200, r.text
    gm = _group_map(r.json())
    assert "整学年" in gm and "上学期" in gm, gm.keys()
    assert gm["整学年"]["active"] == 1


def test_orphan_wrong_question_counted_separately(client: TestClient, db: Session):
    token = _teacher(client, "ana_orphan")
    t = login(client, "ana_orphan", "pw123456").json()["access_token"]
    stu = _make_student(client, token, "6141001", "丁")
    sid = uuid.UUID(stu["id"])
    # 孤儿：指向一个不存在的题目 id。
    orphan_qid = uuid.uuid4()
    db.add(WrongQuestion(student_id=sid, question_id=orphan_qid))
    db.commit()

    r = client.get(
        "/api/v1/analytics/wrong-distribution?scope=student"
        f"&student_id={sid}&dimension=knowledge_point",
        headers=auth_headers(t),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["orphan_count"] >= 1, "孤儿错题应落 orphan_count"
    # 孤儿不会出现在任何分组里。
    assert all(g["total"] == 0 for g in body["groups"])


def test_accuracy_splits_practice_and_review(client: TestClient, db: Session):
    token = _teacher(client, "ana_acc")
    t = login(client, "ana_acc", "pw123456").json()["access_token"]
    me = db.exec(
        select(User).where(User.username == "ana_acc")
    ).first()
    stu = _make_student(client, token, "6151001", "戊")
    sid = uuid.UUID(stu["id"])
    q = _seed_question(db, teacher_id=me.id, subject="数", grade=4, semester="", kp="乘除")
    # 练习：2 对 1 错；复习：1 对 0 错。
    _seed_answer(db, student_id=sid, question_id=q.id, correct=True, source="practice")
    _seed_answer(db, student_id=sid, question_id=q.id, correct=True, source="practice")
    _seed_answer(db, student_id=sid, question_id=q.id, correct=False, source="practice")
    _seed_answer(db, student_id=sid, question_id=q.id, correct=False, source="review")

    r = client.get(
        "/api/v1/analytics/accuracy?scope=student"
        f"&student_id={sid}&dimension=knowledge_point&source=all",
        headers=auth_headers(t),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    g = body["groups"][0]
    assert g["practice"]["total"] == 3 and g["practice"]["correct"] == 2
    assert g["review"]["total"] == 1 and g["review"]["correct"] == 0
    assert g["overall"]["total"] == 4 and g["overall"]["correct"] == 2


def test_mastery_aggregates_across_students(client: TestClient, db: Session):
    token = _teacher(client, "ana_mast")
    t = login(client, "ana_mast", "pw123456").json()["access_token"]
    me = db.exec(
        select(User).where(User.username == "ana_mast")
    ).first()
    s1 = _make_student(client, token, "6161001", "生1")
    s2 = _make_student(client, token, "6161002", "生2")
    q = _seed_question(db, teacher_id=me.id, subject="物", grade=6, semester="", kp="力学")
    # 两名学生都在「力学」上有作答；s1 还有活跃错题 → 该知识点未掌握。
    _seed_answer(db, student_id=uuid.UUID(s1["id"]), question_id=q.id, correct=True, source="practice")
    _seed_answer(db, student_id=uuid.UUID(s2["id"]), question_id=q.id, correct=False, source="practice")
    _seed_wrong(db, student_id=uuid.UUID(s1["id"]), question_id=q.id, graduated=False)

    r = client.get(
        "/api/v1/analytics/mastery?scope=all", headers=auth_headers(t)
    )
    assert r.status_code == 200, r.text
    body = r.json()
    kp = next(i for i in body["items"] if i["knowledge_point"] == "力学")
    assert kp["total_answers"] == 2, "应跨两名学生聚合"
    assert kp["active_wrong"] == 1
    assert kp["level"] != "已掌握", "有活跃错题不该是已掌握"


def test_scope_class_and_cross_teacher_isolation(client: TestClient, db: Session):
    ta = _teacher(client, "ana_cls_a")
    tb = _teacher(client, "ana_cls_b")
    me_a = db.exec(
        select(User).where(User.username == "ana_cls_a")
    ).first()
    cls = client.post(
        "/api/v1/classes", headers=auth_headers(ta),
        json={"name": "统计班", "grade": 3},
    ).json()
    cid = cls["id"]
    # A 的学生（在统计班）：有错题。
    sa = _make_student(client, ta, "6171001", "A生")
    client.post(
        "/api/v1/students/batch-reassign",
        headers=auth_headers(ta),
        json={"class_id": cid, "student_ids": [sa["id"]]},
    )
    q = _seed_question(db, teacher_id=me_a.id, subject="历", grade=3, semester="", kp="朝代")
    _seed_wrong(db, student_id=uuid.UUID(sa["id"]), question_id=q.id, graduated=False)

    # B 的学生：有错题，但属于 B，不该出现在 A 的统计。
    sb = _make_student(client, tb, "6172001", "B生")
    me_b = db.exec(
        select(User).where(User.username == "ana_cls_b")
    ).first()
    qb = _seed_question(db, teacher_id=me_b.id, subject="历", grade=3, semester="", kp="朝代")
    _seed_wrong(db, student_id=uuid.UUID(sb["id"]), question_id=qb.id, graduated=False)

    # A 按班级作用域统计：只应包含 A 的学生。
    r = client.get(
        "/api/v1/analytics/wrong-distribution?scope=class"
        f"&class_id={cid}&dimension=knowledge_point",
        headers=auth_headers(ta),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    gm = _group_map(body)
    assert "朝代" in gm and gm["朝代"]["active"] == 1
    assert body["total"] == 1, "B 的学生不应泄漏进 A 的班级统计"

    # A 越权访问 B 的班级 → 403。
    r2 = client.get(
        "/api/v1/analytics/wrong-distribution?scope=class"
        f"&class_id={cid}&dimension=knowledge_point",
        headers=auth_headers(tb),
    )
    assert r2.status_code == 403, r2.text


def test_large_class_aggregates_without_error(client: TestClient, db: Session):
    """大班（≥60 学生）下批量聚合端点仍能正确返回（性能由单条 GROUP BY 保证）。"""
    token = _teacher(client, "ana_big")
    me = db.exec(
        select(User).where(User.username == "ana_big")
    ).first()
    students = []
    for i in range(60):
        s = _make_student(client, token, f"6{i:08d}", f"大{i}")
        students.append(uuid.UUID(s["id"]))
    q = _seed_question(db, teacher_id=me.id, subject="综", grade=3, semester="", kp="综合")
    for sid in students:
        _seed_wrong(db, student_id=sid, question_id=q.id, graduated=False)

    r = client.get(
        "/api/v1/analytics/mastery?scope=all", headers=auth_headers(token)
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["total_knowledge_points"] == 1
    kp = body["items"][0]
    assert kp["active_wrong"] == 60, "大班下批量聚合应数到全部 60 名活跃错题"
