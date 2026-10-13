"""端点级断言：错题本 / 复习两条链路按端点下发 ADR-0091 新形（ADR-0091 ticket 03）。

为什么是**接口级**而不是只测 service：只测 service 会漏掉某个端点整段忘了下发
新形（历史教训见 ``test_questions_bank_scene.py``）。题库列表端点已由那份文件钉住，
这里补另两条消费端：学生错题本（``GET /tasks/wrong-questions``）与到期复习
（``GET /review/due``）。两者都必须下发 ``SceneSpec`` 新形——顶点在主图形里、
带图库身份键、无顶层 ``points/edges``、无 ``derivedFrom``。
"""
import uuid

from sqlmodel import Session, select

from app.core.db import engine
from app.db.models import WrongQuestion
from tests.utils.user import auth_headers, login, register_teacher


def _create_student(client, ptoken, username):
    r = client.post(
        "/api/v1/students",
        headers=auth_headers(ptoken),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": "学生",
            "grade": 4,
            "role": "student",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def _make_figure_task(client, ptoken, student_id):
    """出题时题面点名「正方形」→ 生成期落库 SceneSpec 新形快照。"""
    r = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(ptoken),
        json={
            "title": "图形题",
            "student_id": student_id,
            "specs": [
                {
                    "subject": "数学",
                    "grade": 4,
                    "knowledge_point": "图形的运动（轴对称）",
                    "qtype": "choice",
                    "difficulty": "easy",
                    "count": 1,
                },
            ],
            "questions": [
                {
                    "subject": "数学",
                    "grade": 4,
                    "knowledge_point": "图形的运动（轴对称）",
                    "qtype": "choice",
                    "difficulty": "easy",
                    "stem": "正方形有几条对称轴？",
                    "options": ["A. 1条", "B. 2条", "C. 3条", "D. 4条"],
                    "answer": "D",
                    "explanation": "正方形有 4 条对称轴。",
                },
            ],
        },
    )
    assert r.status_code == 201, r.text
    tid = r.json()["id"]
    cf = client.post(f"/api/v1/tasks/{tid}/confirm", headers=auth_headers(ptoken))
    assert cf.status_code == 200, cf.text
    ag = client.post(
        f"/api/v1/tasks/{tid}/assign",
        headers=auth_headers(ptoken),
        params={"student_id": student_id},
    )
    assert ag.status_code == 200, ag.text
    return ag.json()


def _answer_wrong(client, ctoken, task):
    q = task["questions"][0]
    r = client.post(
        f"/api/v1/tasks/{task['id']}/answer",
        headers=auth_headers(ctoken),
        json={"question_id": q["question_id"], "student_answer": "__wrong__"},
    )
    assert r.status_code == 200, r.text


def _load_wq(student_id, question_id) -> WrongQuestion:
    with Session(engine) as s:
        return s.exec(
            select(WrongQuestion).where(
                WrongQuestion.student_id == uuid.UUID(student_id),
                WrongQuestion.question_id == uuid.UUID(question_id),
            )
        ).one()


def test_wrong_questions_issues_scene_spec_new_shape(client):
    """学生错题本必须下发 SceneSpec 新形（顶点在主图形、带图库 key）。"""
    r = register_teacher(client, username="wq_scene_teacher")
    ptoken = r.json()["access_token"]
    student = _create_student(client, ptoken, "wq_scene_kid")
    task = _make_figure_task(client, ptoken, student["id"])
    lr = login(client, "wq_scene_kid", "kid123456")
    ctoken = lr.json()["access_token"]
    _answer_wrong(client, ctoken, task)

    items = client.get(
        "/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken)
    ).json()["items"]
    item = next(i for i in items if "正方形" in i["stem"])
    spec = item["scene_spec"]
    assert spec is not None, "错题本 no 图形：scene_spec 不应为 null"
    assert set(spec) == {"kind", "figure", "options", "curated"}
    assert spec["figure"]["key"] == "square"
    assert "derivedFrom" not in spec
    assert len(spec["figure"]["points"]) == 4


def test_review_due_issues_scene_spec_new_shape(client):
    """到期复习必须下发 SceneSpec 新形（与错题本同一份几何，不双读）。"""
    r = register_teacher(client, username="rv_scene_teacher")
    ptoken = r.json()["access_token"]
    student = _create_student(client, ptoken, "rv_scene_kid")
    task = _make_figure_task(client, ptoken, student["id"])
    lr = login(client, "rv_scene_kid", "kid123456")
    ctoken = lr.json()["access_token"]
    _answer_wrong(client, ctoken, task)

    wq = _load_wq(student["id"], task["questions"][0]["question_id"])
    with Session(engine) as s:
        w = s.get(WrongQuestion, wq.id)
        w.review_stage = 0
        w.due_at = w.due_at  # 保持；强制到期由时间偏移处理
        from datetime import UTC, datetime, timedelta

        w.due_at = datetime.now(UTC) - timedelta(minutes=5)
        s.add(w)
        s.commit()

    due = client.get("/api/v1/review/due", headers=auth_headers(ctoken)).json()
    item = next(i for i in due if "正方形" in i["stem"])
    spec = item["scene_spec"]
    assert spec is not None
    assert set(spec) == {"kind", "figure", "options", "curated"}
    assert spec["figure"]["key"] == "square"
    assert len(spec["figure"]["points"]) == 4
