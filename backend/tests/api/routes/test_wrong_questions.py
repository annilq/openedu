"""错题自动归集单测（T04，故事 13）。

覆盖：正确作答不归集、答错归集（教师/学生可查）、重复错不建多条（wrong_count 递增）。
"""
from tests.utils.paging import page_items
from tests.utils.user import auth_headers, login, register_teacher


def _create_student(client, ptoken, username="wq_kid"):
    r = client.post(
        "/api/v1/students",
        headers=auth_headers(ptoken),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": "学生",
            "grade": 2,
            "role": "student",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def _make_task(client, ptoken, student_id, count=1):
    # 单流：以「已生成题卡」直接落库（POST /tasks/from-generated，唯一业务写库点，ADR-0023）。
    specs = [
        {
            "subject": "数学",
            "grade": 2,
            "knowledge_point": "加法",
            "qtype": "calc",
            "difficulty": "easy",
            "count": count,
        },
    ]
    # 预设 count 道确定性题卡（answer 与序号一一对应，便于测试断言）。
    questions = [
        {
            "subject": "数学",
            "grade": 2,
            "knowledge_point": "加法",
            "qtype": "calc",
            "difficulty": "easy",
            "stem": f"加法练习 {i}",
            "options": None,
            "answer": f"ans{i}",
            "explanation": f"第 {i} 题解析。",
        }
        for i in range(count)
    ]
    r = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(ptoken),
        json={
            "title": "错题测试",
            "student_id": student_id,
            "specs": specs,
            "questions": questions,
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
        params={"student_id": student_id},
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


def _setup(client, teacher_username, student_username):
    r = register_teacher(client, username=teacher_username)
    assert r.status_code == 200
    ptoken = r.json()["access_token"]
    student = _create_student(client, ptoken, username=student_username)
    task = _make_task(client, ptoken, student["id"])
    lr = login(client, student_username, "kid123456")
    assert lr.status_code == 200
    return ptoken, student, task, lr.json()["access_token"]


def test_correct_answer_not_collected(client):
    """正确作答不归集：答对后学生/教师的错题列表均为空。"""
    ptoken, _student, task, ctoken = _setup(client, "wq1_teacher", "wq1_kid")
    q = task["questions"][0]
    result = _answer(client, ctoken, task["id"], q["question_id"], q["answer"])
    assert result["correct"] is True

    mine = client.get("/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken))
    assert mine.status_code == 200 and page_items(mine) == []

    # 教师视角同样为空
    by_teacher = client.get(
        f"/api/v1/tasks/students/{_student['id']}/wrong-questions",
        headers=auth_headers(ptoken),
    )
    assert by_teacher.status_code == 200 and page_items(by_teacher) == []


def test_wrong_answer_collected_with_full_fields(client):
    """答错归集：教师/学生都能查到；学生端不含答案（防作弊），教师端含答案供核查。"""
    ptoken, student, task, ctoken = _setup(client, "wq2_teacher", "wq2_kid")
    q = task["questions"][0]
    result = _answer(client, ctoken, task["id"], q["question_id"], "__wrong__")
    assert result["correct"] is False

    mine = client.get("/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken))
    assert mine.status_code == 200
    items = page_items(mine)
    assert len(items) == 1
    item = items[0]
    assert item["question_id"] == q["question_id"]
    assert item["subject"] == "数学" and item["grade"] == 2
    assert item["stem"] == q["stem"]
    assert item["answer"] is None  # 学生端防作弊
    assert item["explanation"]
    assert item["wrong_count"] == 1
    assert item["first_wrong_at"] is not None

    by_teacher = client.get(
        f"/api/v1/tasks/students/{student['id']}/wrong-questions",
        headers=auth_headers(ptoken),
    )
    assert by_teacher.status_code == 200
    teachers = page_items(by_teacher)
    assert len(teachers) == 1
    assert teachers[0]["question_id"] == q["question_id"]
    assert teachers[0]["answer"] == q["answer"]  # 教师端含答案


def test_repeat_wrong_not_duplicated(client):
    """同一题重复答错：只保留一条，wrong_count 递增。"""
    ptoken, student, task, ctoken = _setup(client, "wq3_teacher", "wq3_kid")
    q = task["questions"][0]
    for _ in range(3):
        _answer(client, ctoken, task["id"], q["question_id"], "__wrong__")

    mine = client.get("/api/v1/tasks/wrong-questions", headers=auth_headers(ctoken))
    assert mine.status_code == 200
    items = page_items(mine)
    assert len(items) == 1  # 不建多条
    assert items[0]["wrong_count"] == 3
    assert items[0]["first_wrong_at"] is not None


def test_wrong_questions_permission(client):
    """权限边界：学生不能查教师接口，教师不能查别人的学生。"""
    ptoken, _student, task, ctoken = _setup(client, "wq4_teacher", "wq4_kid")
    _answer(client, ctoken, task["id"], task["questions"][0]["question_id"], "__wrong__")

    # 学生调教师接口（CurrentTeacher）-> 403
    bad = client.get(
        f"/api/v1/tasks/students/{_student['id']}/wrong-questions",
        headers=auth_headers(ctoken),
    )
    assert bad.status_code == 403

    # 教师查别人的学生 -> 403
    other_teacher = register_teacher(client, username="wq4_other")
    assert other_teacher.status_code == 200
    opt = other_teacher.json()["access_token"]
    stranger = client.get(
        f"/api/v1/tasks/students/{_student['id']}/wrong-questions",
        headers=auth_headers(opt),
    )
    assert stranger.status_code == 403
