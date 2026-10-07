"""GET /api/v1/assistant/suggested-actions 端点单测（ADR-0072 推荐操作目录）。

不接 LLM：目录是服务端静态装配。覆盖：
- 全局目录（不带 knowledge_point_id）：教师 4 项，导航标签为「看看孩子错题」。
- 知识点目录（带归属通过的 id）：叠加知识点动作（含 quiz 判断题），共 7 项。
- 知识点 id 未知 / 查不到：回落全局目录（不抛错）。
"""
import uuid

from sqlmodel import select

from app.db.models import User
from app.db.models.material import KnowledgePoint
from tests.utils.user import auth_headers, register_teacher


def _teacher_id(db, username: str) -> uuid.UUID:
    return db.exec(select(User).where(User.username == username)).one().id


def test_suggested_actions_global_for_teacher(client, db):
    """无知识点 id：返回全局 4 项，教师导航标签为「看看孩子错题」。"""
    r = register_teacher(client, username="sa_teacher")
    token = r.json()["access_token"]

    resp = client.get(
        "/api/v1/assistant/suggested-actions", headers=auth_headers(token)
    )
    assert resp.status_code == 200, resp.text
    actions = resp.json()
    assert len(actions) == 4
    labels = [a["label"] for a in actions]
    assert "看看孩子错题" in labels
    assert all(a["quiz"] is False for a in actions)


def test_suggested_actions_with_owned_kp_prepend(client, db):
    """带归属通过的知识点 id：前 3 项为知识点动作，共 7 项，判断题动作 quiz=true。"""
    r = register_teacher(client, username="sa_kp_teacher")
    token = r.json()["access_token"]
    tid = _teacher_id(db, "sa_kp_teacher")

    kp = KnowledgePoint(
        teacher_id=tid, subject="数学", grade=4, semester="下学期", name="轴对称"
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)

    resp = client.get(
        "/api/v1/assistant/suggested-actions",
        headers=auth_headers(token),
        params={"knowledge_point_id": str(kp.id)},
    )
    assert resp.status_code == 200, resp.text
    actions = resp.json()
    assert len(actions) == 7
    labels = [a["label"] for a in actions]
    assert labels[:3] == ["举几个生活例子", "出一道判断题", "讲解这个知识点"]

    quiz = [a for a in actions if a["label"] == "出一道判断题"][0]
    assert quiz["kind"] == "prompt" and quiz["quiz"] is True
    assert "轴对称" in quiz["payload"]


def test_suggested_actions_unknown_kp_falls_back(client, db):
    """知识点 id 不存在：回落全局目录（4 项，不出现知识点动作）。"""
    r = register_teacher(client, username="sa_unknown_teacher")
    token = r.json()["access_token"]

    resp = client.get(
        "/api/v1/assistant/suggested-actions",
        headers=auth_headers(token),
        params={"knowledge_point_id": str(uuid.uuid4())},
    )
    assert resp.status_code == 200, resp.text
    actions = resp.json()
    assert len(actions) == 4
    assert all(a["quiz"] is False for a in actions)
