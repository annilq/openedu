"""知识点掌握度看板 API 单测（T06，F-204 / AC-203）。

覆盖：初始看板为空、答错→复习→毕业全链路看板分数与等级联动、越权 403。
"""
import uuid
from datetime import UTC, datetime, timedelta

from sqlmodel import Session, select

from app.core.db import engine
from app.models import WrongQuestion
from tests.utils.user import auth_headers, login, register_parent


def _create_child(client, ptoken, username="mk_kid"):
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


def _make_task(client, ptoken, child_id, count=1):
    # 批量生成 draft 草稿（ADR-0004 D4）
    r = client.post(
        "/api/v1/tasks/batch-generate",
        headers=auth_headers(ptoken),
        json={
            "title": "掌握度测试",
            "child_id": child_id,
            "specs": [
                {
                    "subject": "数学",
                    "grade": 2,
                    "knowledge_point": "加法",
                    "qtype": "calc",
                    "difficulty": "easy",
                    "count": count,
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


def _answer(client, ctoken, task_id, question_id, student_answer):
    r = client.post(
        f"/api/v1/tasks/{task_id}/answer",
        headers=auth_headers(ctoken),
        json={"question_id": question_id, "student_answer": student_answer},
    )
    assert r.status_code == 200, r.text
    return r.json()


def _get_mastery(client, ptoken, child_id):
    r = client.get(
        f"/api/v1/tasks/children/{child_id}/mastery",
        headers=auth_headers(ptoken),
    )
    assert r.status_code == 200, r.text
    return r.json()


def _force_due(wrong_question_id, *, stage=0):
    with Session(engine) as s:
        wq = s.get(WrongQuestion, uuid.UUID(wrong_question_id))
        assert wq is not None
        wq.review_stage = stage
        wq.due_at = datetime.now(UTC) - timedelta(minutes=5)
        s.add(wq)
        s.commit()


def _load_wq(child_id, question_id) -> WrongQuestion:
    with Session(engine) as s:
        return s.exec(
            select(WrongQuestion).where(
                WrongQuestion.child_id == uuid.UUID(child_id),
                WrongQuestion.question_id == uuid.UUID(question_id),
            )
        ).one()


def _review(client, ctoken, wrong_question_id, student_answer):
    r = client.post(
        "/api/v1/review/answer",
        headers=auth_headers(ctoken),
        json={"wrong_question_id": wrong_question_id, "student_answer": student_answer},
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_empty_mastery(client):
    """新娃娃还没有任何作答：看板为空。"""
    r = register_parent(client, username="mk0_parent")
    ptoken = r.json()["access_token"]
    child = _create_child(client, ptoken, username="mk0_kid")

    board = _get_mastery(client, ptoken, child["id"])
    assert board["child_id"] == child["id"]
    assert board["total_knowledge_points"] == 0
    assert board["mastered_count"] == 0
    assert board["items"] == []


def test_wrong_review_graduate_flow(client):
    """AC-203 全链路：答错后分数被封顶压住 → 复习答对推进阶段分数上升 → 毕业解除封顶达到已掌握。"""
    r = register_parent(client, username="mk1_parent")
    ptoken = r.json()["access_token"]
    child = _create_child(client, ptoken, username="mk1_kid")
    task = _make_task(client, ptoken, child["id"], count=6)
    lr = login(client, "mk1_kid", "kid123456")
    ctoken = lr.json()["access_token"]

    # 答对 5 题、答错 1 题（错题入集）
    wrong_question = None
    for q in task["questions"]:
        res = _answer(
            client, ctoken, task["id"], q["question_id"], "__wrong__" if wrong_question is None else q["answer"]
        )
        if not res["correct"]:
            wrong_question = _load_wq(child["id"], q["question_id"])
    assert wrong_question is not None

    # 答错后：正确率虽高，但活跃错题把分数封顶在 60（薄弱）
    board = _get_mastery(client, ptoken, child["id"])
    assert board["total_knowledge_points"] == 1
    kp = board["items"][0]
    assert kp["knowledge_point"] == "加法"
    assert kp["total_answers"] == 6 and kp["correct_answers"] == 5
    assert kp["active_wrong"] == 1 and kp["max_review_stage"] == 0
    assert kp["score"] == 60.0
    assert kp["level"] == "薄弱"

    # 复习答对一次：阶段推进 → 封顶提高 → 分数上升（AC-203）
    wrong_q = next(q for q in task["questions"] if q["question_id"] == str(wrong_question.question_id))
    _force_due(str(wrong_question.id), stage=0)
    _review(client, ctoken, str(wrong_question.id), wrong_q["answer"])
    board = _get_mastery(client, ptoken, child["id"])
    kp = board["items"][0]
    assert kp["total_answers"] == 7 and kp["correct_answers"] == 6
    assert kp["active_wrong"] == 1 and kp["max_review_stage"] == 1
    assert kp["score"] == 66.0
    assert kp["level"] == "薄弱"

    # 末位阶段（15 天档）复习答对：毕业，解除封顶 → 已掌握（AC-203）
    _force_due(str(wrong_question.id), stage=4)
    _review(client, ctoken, str(wrong_question.id), wrong_q["answer"])
    board = _get_mastery(client, ptoken, child["id"])
    kp = board["items"][0]
    assert kp["total_answers"] == 8 and kp["correct_answers"] == 7
    assert kp["active_wrong"] == 0
    assert kp["score"] == 87.5
    assert kp["level"] == "已掌握"
    assert board["mastered_count"] == 1


def test_mastery_forbidden_for_other_parent(client):
    """越权：别的家长查不了这个娃娃的看板（403）。"""
    r = register_parent(client, username="mk2_parent")
    ptoken = r.json()["access_token"]
    child = _create_child(client, ptoken, username="mk2_kid")
    # 给这个娃娃造一条作答记录，避免「无记录」歧义
    task = _make_task(client, ptoken, child["id"], count=1)
    lr = login(client, "mk2_kid", "kid123456")
    _answer(client, lr.json()["access_token"], task["id"], task["questions"][0]["question_id"], "__wrong__")

    other = register_parent(client, username="mk2_other")
    other_token = other.json()["access_token"]
    r = client.get(
        f"/api/v1/tasks/children/{child['id']}/mastery",
        headers=auth_headers(other_token),
    )
    assert r.status_code == 403


def test_mastery_forbidden_for_child(client):
    """娃娃 token 不能访问家长看板接口（403，require_parent）。"""
    r = register_parent(client, username="mk3_parent")
    ptoken = r.json()["access_token"]
    child = _create_child(client, ptoken, username="mk3_kid")
    lr = login(client, "mk3_kid", "kid123456")
    ctoken = lr.json()["access_token"]

    r = client.get(
        f"/api/v1/tasks/children/{child['id']}/mastery",
        headers=auth_headers(ctoken),
    )
    assert r.status_code == 403
