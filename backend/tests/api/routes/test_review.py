"""遗忘曲线复习 API 单测（T05，故事 14/15/17）。

覆盖：到期过滤（未到期不出现）、复习答对推进阶段、末位答对毕业移除、
复习答错重置计时器、权限边界。
"""
import uuid
from datetime import UTC, datetime, timedelta

from sqlmodel import Session, select

from app.core.db import engine
from app.models import AnswerRecord, WrongQuestion
from tests.utils.user import auth_headers, login, register_parent


def _create_child(client, ptoken, username="rv_kid"):
    r = client.post(
        "/api/v1/children",
        headers=auth_headers(ptoken),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": "娃娃",
            "grade": 2,
            "role": "child",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def _make_task(client, ptoken, child_id):
    # 批量生成 draft 草稿（ADR-0004 D4）
    r = client.post(
        "/api/v1/tasks/batch-generate",
        headers=auth_headers(ptoken),
        json={
            "title": "复习测试",
            "child_id": child_id,
            "specs": [
                {
                    "subject": "数学",
                    "grade": 2,
                    "knowledge_point": "加法",
                    "qtype": "calc",
                    "difficulty": "easy",
                    "count": 1,
                },
            ],
        },
    )
    assert r.status_code == 201, r.text
    tid = r.json()["id"]
    # 确认成卷 draft → ready + 派发 ready → assigned（ADR-0004 D7）
    cf = client.post(f"/api/v1/tasks/{tid}/confirm", headers=auth_headers(ptoken))
    assert cf.status_code == 200, cf.text
    ag = client.post(
        f"/api/v1/tasks/{tid}/assign",
        headers=auth_headers(ptoken),
        params={"child_id": child_id},
    )
    assert ag.status_code == 200, ag.text
    return ag.json()


def _answer_wrong(client, ctoken, task, student_answer="__wrong__"):
    q = task["questions"][0]
    r = client.post(
        f"/api/v1/tasks/{task['id']}/answer",
        headers=auth_headers(ctoken),
        json={"question_id": q["question_id"], "student_answer": student_answer},
    )
    assert r.status_code == 200, r.text
    return q, r.json()


def _setup(client, parent_username, child_username):
    r = register_parent(client, username=parent_username)
    assert r.status_code == 200
    ptoken = r.json()["access_token"]
    child = _create_child(client, ptoken, username=child_username)
    task = _make_task(client, ptoken, child["id"])
    lr = login(client, child_username, "kid123456")
    assert lr.status_code == 200
    ctoken = lr.json()["access_token"]
    q, _ = _answer_wrong(client, ctoken, task)
    return ptoken, child, task, ctoken, q


def _load_wq(child_id, question_id) -> WrongQuestion:
    with Session(engine) as s:
        return s.exec(
            select(WrongQuestion).where(
                WrongQuestion.child_id == uuid.UUID(child_id),
                WrongQuestion.question_id == uuid.UUID(question_id),
            )
        ).one()


def _force_state(wrong_question_id, *, stage=0, due_in_past=True):
    with Session(engine) as s:
        wq = s.get(WrongQuestion, wrong_question_id)
        assert wq is not None
        wq.review_stage = stage
        wq.due_at = (
            datetime.now(UTC) - timedelta(minutes=5) if due_in_past else datetime.now(UTC) + timedelta(days=1)
        )
        s.add(wq)
        s.commit()


def test_not_due_until_interval_elapses(client):
    """刚答错的题 1 天后才到期：初始 /review/due 为空，强制到期后出现且不含答案。"""
    _ptoken, child, _task, ctoken, q = _setup(client, "rv1_parent", "rv1_kid")

    r = client.get("/api/v1/review/due", headers=auth_headers(ctoken))
    assert r.status_code == 200 and r.json() == []

    wq = _load_wq(child["id"], q["question_id"])
    _force_state(wq.id)

    r = client.get("/api/v1/review/due", headers=auth_headers(ctoken))
    assert r.status_code == 200
    items = r.json()
    assert len(items) == 1
    item = items[0]
    assert item["question_id"] == q["question_id"]
    assert item["wrong_question_id"] == str(wq.id)
    assert item["stem"] == q["stem"]
    assert item["wrong_count"] == 1
    assert item["review_stage"] == 0
    assert item["next_interval_days"] == 1
    assert "answer" not in item  # 娃娃端防作弊


def test_correct_review_advances_stage(client):
    """复习答对：阶段推进（0→1），下次间隔 2 天，错题仍在错题本。"""
    _ptoken, child, task, ctoken, q = _setup(client, "rv2_parent", "rv2_kid")
    wq = _load_wq(child["id"], q["question_id"])
    _force_state(wq.id)

    r = client.post(
        "/api/v1/review/answer",
        headers=auth_headers(ctoken),
        json={"wrong_question_id": str(wq.id), "student_answer": q["answer"]},
    )
    assert r.status_code == 200
    assert r.json()["correct"] is True

    with Session(engine) as s:
        refreshed = s.get(WrongQuestion, wq.id)
        assert refreshed.review_stage == 1
        assert refreshed.due_at is not None
        # SQLite 读出 naive UTC；距当前应大于 1 天（间隔 2 天）
        naive_now = datetime.now(UTC).replace(tzinfo=None)
        assert refreshed.due_at > naive_now + timedelta(days=1)
        # 作答记录来源标记为 review
        rec = s.exec(
            select(AnswerRecord).where(
                AnswerRecord.question_id == uuid.UUID(q["question_id"]),
                AnswerRecord.source == "review",
            )
        ).first()
        assert rec is not None

    # 错题本仍有（未毕业）
    mine = client.get("/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken))
    assert len(mine.json()) == 1
    assert mine.json()[0]["review_stage"] == 1


def test_final_correct_review_graduates(client):
    """末位阶段（15 天档）复习答对：视为掌握，从错题集移除。"""
    _ptoken, child, task, ctoken, q = _setup(client, "rv3_parent", "rv3_kid")
    wq = _load_wq(child["id"], q["question_id"])
    _force_state(wq.id, stage=4)

    r = client.post(
        "/api/v1/review/answer",
        headers=auth_headers(ctoken),
        json={"wrong_question_id": str(wq.id), "student_answer": q["answer"]},
    )
    assert r.status_code == 200 and r.json()["correct"] is True

    mine = client.get("/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken))
    assert mine.json() == []  # 已毕业

    due = client.get("/api/v1/review/due", headers=auth_headers(ctoken))
    assert due.json() == []


def test_wrong_review_resets_timer(client):
    """复习答错：计时器重置回 1 天首档，wrong_count 递增（故事 17）。"""
    _ptoken, child, task, ctoken, q = _setup(client, "rv4_parent", "rv4_kid")
    wq = _load_wq(child["id"], q["question_id"])
    _force_state(wq.id, stage=2)

    r = client.post(
        "/api/v1/review/answer",
        headers=auth_headers(ctoken),
        json={"wrong_question_id": str(wq.id), "student_answer": "__wrong__"},
    )
    assert r.status_code == 200 and r.json()["correct"] is False

    with Session(engine) as s:
        refreshed = s.get(WrongQuestion, wq.id)
        assert refreshed.review_stage == 0
        assert refreshed.wrong_count == 2
        naive_now = datetime.now(UTC).replace(tzinfo=None)
        assert refreshed.due_at <= naive_now + timedelta(days=1, minutes=5)


def test_review_before_due_rejected(client):
    """未到期提交复习被拒（409）：防止连对提前毕业绕过遗忘曲线。"""
    _ptoken, child, _task, ctoken, q = _setup(client, "rv6_parent", "rv6_kid")
    wq = _load_wq(child["id"], q["question_id"])  # due 为 1 天后，未到期

    r = client.post(
        "/api/v1/review/answer",
        headers=auth_headers(ctoken),
        json={"wrong_question_id": str(wq.id), "student_answer": q["answer"]},
    )
    assert r.status_code == 409


def test_graduate_then_wrong_again_recollects(client):
    """毕业移除后再次答错：重新归集为新错题（计时器从头开始）。"""
    _ptoken, child, task, ctoken, q = _setup(client, "rv7_parent", "rv7_kid")
    wq = _load_wq(child["id"], q["question_id"])
    _force_state(wq.id, stage=4)
    # 末位答对毕业
    r = client.post(
        "/api/v1/review/answer",
        headers=auth_headers(ctoken),
        json={"wrong_question_id": str(wq.id), "student_answer": q["answer"]},
    )
    assert r.status_code == 200 and r.json()["correct"] is True
    assert client.get("/api/v1/review/due", headers=auth_headers(ctoken)).json() == []

    # 同一题再答错 -> 重新归集
    q2, _ = _answer_wrong(client, ctoken, task)
    assert q2["question_id"] == q["question_id"]
    mine = client.get("/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken))
    assert len(mine.json()) == 1
    assert mine.json()[0]["wrong_count"] == 1
    assert mine.json()[0]["review_stage"] == 0


def test_review_answer_ownership(client):
    """权限边界：娃娃不能复习别人的复习项（404）。"""
    _ptoken, _child, _task, ctoken, q = _setup(client, "rv5_parent", "rv5_kid")
    other_parent = register_parent(client, username="rv5_other")
    other_child = _create_child(client, other_parent.json()["access_token"], username="rv5_other_kid")
    other_task = _make_task(client, other_parent.json()["access_token"], other_child["id"])
    other_login = login(client, "rv5_other_kid", "kid123456")
    other_ctoken = other_login.json()["access_token"]
    other_q, _ = _answer_wrong(client, other_ctoken, other_task)

    wq = _load_wq(other_child["id"], other_q["question_id"])
    r = client.post(
        "/api/v1/review/answer",
        headers=auth_headers(ctoken),  # rv5_kid 拿 rv5_other_kid 的复习项
        json={"wrong_question_id": str(wq.id), "student_answer": "1"},
    )
    assert r.status_code == 404
