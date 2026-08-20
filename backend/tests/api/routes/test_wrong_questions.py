"""错题自动归集单测（T04，故事 13）。

覆盖：正确作答不归集、答错归集（家长/娃娃可查）、重复错不建多条（wrong_count 递增）。
"""
from tests.utils.user import auth_headers, login, register_parent


def _create_child(client, ptoken, username="wq_kid"):
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
    r = client.post(
        "/api/v1/tasks",
        headers=auth_headers(ptoken),
        json={
            "title": "错题测试",
            "subject": "数学",
            "grade": 2,
            "knowledge_point": "加法",
            "qtype": "calc",
            "difficulty": "easy",
            "count": count,
            "child_id": child_id,
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def _answer(client, ctoken, task_id, question_id, student_answer):
    r = client.post(
        f"/api/v1/tasks/{task_id}/answer",
        headers=auth_headers(ctoken),
        json={"question_id": question_id, "student_answer": student_answer},
    )
    assert r.status_code == 200, r.text
    return r.json()


def _setup(client, parent_username, child_username):
    r = register_parent(client, username=parent_username)
    assert r.status_code == 200
    ptoken = r.json()["access_token"]
    child = _create_child(client, ptoken, username=child_username)
    task = _make_task(client, ptoken, child["id"])
    lr = login(client, child_username, "kid123456")
    assert lr.status_code == 200
    return ptoken, child, task, lr.json()["access_token"]


def test_correct_answer_not_collected(client):
    """正确作答不归集：答对后娃娃/家长的错题列表均为空。"""
    ptoken, _child, task, ctoken = _setup(client, "wq1_parent", "wq1_kid")
    q = task["questions"][0]
    result = _answer(client, ctoken, task["id"], q["id"], q["answer"])
    assert result["correct"] is True

    mine = client.get("/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken))
    assert mine.status_code == 200 and mine.json() == []

    # 家长视角同样为空
    by_parent = client.get(
        f"/api/v1/tasks/children/{_child['id']}/wrong-questions",
        headers=auth_headers(ptoken),
    )
    assert by_parent.status_code == 200 and by_parent.json() == []


def test_wrong_answer_collected_with_full_fields(client):
    """答错归集：家长/娃娃都能查到；娃娃端不含答案（防作弊），家长端含答案供核查。"""
    ptoken, child, task, ctoken = _setup(client, "wq2_parent", "wq2_kid")
    q = task["questions"][0]
    result = _answer(client, ctoken, task["id"], q["id"], "__wrong__")
    assert result["correct"] is False

    mine = client.get("/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken))
    assert mine.status_code == 200
    items = mine.json()
    assert len(items) == 1
    item = items[0]
    assert item["question_id"] == q["id"]
    assert item["subject"] == "数学" and item["grade"] == 2
    assert item["stem"] == q["stem"]
    assert item["answer"] is None  # 娃娃端防作弊
    assert item["explanation"]
    assert item["wrong_count"] == 1
    assert item["first_wrong_at"] is not None

    by_parent = client.get(
        f"/api/v1/tasks/children/{child['id']}/wrong-questions",
        headers=auth_headers(ptoken),
    )
    assert by_parent.status_code == 200
    assert len(by_parent.json()) == 1
    assert by_parent.json()[0]["question_id"] == q["id"]
    assert by_parent.json()[0]["answer"] == q["answer"]  # 家长端含答案


def test_repeat_wrong_not_duplicated(client):
    """同一题重复答错：只保留一条，wrong_count 递增。"""
    ptoken, child, task, ctoken = _setup(client, "wq3_parent", "wq3_kid")
    q = task["questions"][0]
    for _ in range(3):
        _answer(client, ctoken, task["id"], q["id"], "__wrong__")

    mine = client.get("/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken))
    assert mine.status_code == 200
    items = mine.json()
    assert len(items) == 1  # 不建多条
    assert items[0]["wrong_count"] == 3
    assert items[0]["first_wrong_at"] is not None


def test_wrong_questions_permission(client):
    """权限边界：娃娃不能查家长接口，家长不能查别人的娃娃。"""
    ptoken, _child, task, ctoken = _setup(client, "wq4_parent", "wq4_kid")
    _answer(client, ctoken, task["id"], task["questions"][0]["id"], "__wrong__")

    # 娃娃调家长接口（CurrentParent）-> 403
    bad = client.get(
        f"/api/v1/tasks/children/{_child['id']}/wrong-questions",
        headers=auth_headers(ctoken),
    )
    assert bad.status_code == 403

    # 家长查别人的娃娃 -> 403
    other_parent = register_parent(client, username="wq4_other")
    assert other_parent.status_code == 200
    opt = other_parent.json()["access_token"]
    stranger = client.get(
        f"/api/v1/tasks/children/{_child['id']}/wrong-questions",
        headers=auth_headers(opt),
    )
    assert stranger.status_code == 403
