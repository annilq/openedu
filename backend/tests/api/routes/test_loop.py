from tests.utils.user import auth_headers, login, register_parent


def _create_child(client, ptoken, username="kid1"):
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


def test_full_closed_loop(client):
    # 1) 注册家长
    r = register_parent(client)
    assert r.status_code == 200
    ptoken = r.json()["access_token"]

    # 2) 加娃娃
    child = _create_child(client, ptoken)
    cid = child["id"]

    # 3) 家长多科一卷批量生成（draft 态，含答案，ADR-0004 D4）
    gen = client.post(
        "/api/v1/tasks/batch-generate",
        headers=auth_headers(ptoken),
        json={
            "title": "二年级混合卷",
            "child_id": cid,
            "specs": [
                {
                    "subject": "数学",
                    "grade": 2,
                    "knowledge_point": "加法",
                    "qtype": "calc",
                    "difficulty": "easy",
                    "count": 2,
                },
            ],
        },
    )
    assert gen.status_code == 201, gen.text
    task = gen.json()
    assert task["status"] == "draft"
    assert len(task["questions"]) == 2
    # 家长端能看到答案（审阅质量）
    assert task["questions"][0]["answer"] is not None
    tid = task["id"]
    # 4) 家长确认成卷 draft → ready（ADR-0004 D7）
    cf = client.post(f"/api/v1/tasks/{tid}/confirm", headers=auth_headers(ptoken))
    assert cf.status_code == 200, cf.text
    assert cf.json()["status"] == "ready"
    # question_id = 源 Question.id 在 confirm promote 后才落盘
    confirmed = cf.json()
    q0_question_id = confirmed["questions"][0]["question_id"]
    q0_answer = confirmed["questions"][0]["answer"]
    q1_question_id = confirmed["questions"][1]["question_id"]

    # 5) 家长派发 ready → assigned（绑 child_id，ADR-0004 D7）
    ag = client.post(
        f"/api/v1/tasks/{tid}/assign",
        headers=auth_headers(ptoken),
        params={"child_id": cid},
    )
    assert ag.status_code == 200, ag.text
    assert ag.json()["status"] == "assigned"

    # 6) 娃娃登录
    lr = login(client, "kid1", "kid123456")
    assert lr.status_code == 200
    ctoken = lr.json()["access_token"]

    # 7) 今日任务：娃娃端看不到答案
    today = client.get("/api/v1/tasks/today", headers=auth_headers(ctoken))
    assert today.status_code == 200
    assert today.json()[0]["questions"][0]["answer"] is None

    # 8) 作答：第一题答对，第二题答错（提交 question_id = 源 Question.id）
    a1 = client.post(
        f"/api/v1/tasks/{tid}/answer",
        headers=auth_headers(ctoken),
        json={"question_id": q0_question_id, "student_answer": q0_answer},
    )
    assert a1.status_code == 200 and a1.json()["correct"] is True
    a2 = client.post(
        f"/api/v1/tasks/{tid}/answer",
        headers=auth_headers(ctoken),
        json={"question_id": q1_question_id, "student_answer": "__wrong__"},
    )
    assert a2.status_code == 200 and a2.json()["correct"] is False

    # 9) 打卡（assigned → done）
    ck = client.post(f"/api/v1/tasks/{tid}/checkin", headers=auth_headers(ctoken))
    assert ck.status_code == 200 and ck.json()["ok"] is True

    # 10) 进度
    pr = client.get(
        f"/api/v1/tasks/children/{cid}/progress", headers=auth_headers(ptoken)
    )
    assert pr.status_code == 200
    pj = pr.json()
    assert pj["total"] == 2 and pj["correct"] == 1
    assert pj["accuracy"] == 0.5
    assert pj["streak_days"] == 1


def test_error_paths(client):
    # 重复注册 -> 400
    register_parent(client, username="dup")
    r2 = register_parent(client, username="dup")
    assert r2.status_code == 400

    # 娃娃调用家长接口（加娃娃） -> 403
    lr = login(client, "kid1", "kid123456")
    ctoken = lr.json()["access_token"]
    bad = client.post(
        "/api/v1/children",
        headers=auth_headers(ctoken),
        json={"username": "x", "password": "y", "display_name": "z", "role": "child"},
    )
    assert bad.status_code == 403

    # 未登录访问受保护接口 -> 401
    noauth = client.get("/api/v1/children")
    assert noauth.status_code == 401


def test_auth_me(client):
    """前端登录后用 token 调 /auth/me 获取当前用户信息。"""
    # 家长注册（用唯一用户名避免与其它测试冲突）
    r = register_parent(client, username="me_parent")
    assert r.status_code == 200, r.text
    ptoken = r.json()["access_token"]

    # 调 /auth/me 应返回家长信息
    me = client.get("/api/v1/auth/me", headers=auth_headers(ptoken))
    assert me.status_code == 200
    me_json = me.json()
    assert me_json["role"] == "parent"
    assert me_json["username"] == "me_parent"
    assert "id" in me_json

    # 创建娃娃并验证 /auth/me 返回 child 角色
    _create_child(client, ptoken, username="kid_me")
    lr = login(client, "kid_me", "kid123456")
    assert lr.status_code == 200
    ctoken = lr.json()["access_token"]

    me2 = client.get("/api/v1/auth/me", headers=auth_headers(ctoken))
    assert me2.status_code == 200
    assert me2.json()["role"] == "child"
    assert me2.json()["grade"] == 2
