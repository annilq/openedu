"""打印导出 HTTP 接缝测试（主接缝：``POST /export/sheet``）。

归属校验（别人的题 / 别人的娃娃）、错误语义（400 / 403 / 503）与
「返回的真的是一份 PDF」都在这里断言；内容规则（分节 / 题号 / 无答案）
在 ``tests/features/export/test_document.py`` 的文档模型层断言——
Typst 会子集化字体，PDF 文本层 grep 不到内容，别在二进制上打转。
"""
import uuid

import pytest
from sqlmodel import Session, select

from app.core.config import settings
from app.db.models import Question, User
from tests.utils.user import auth_headers, login, register_parent


def _parent_id(db: Session, username: str) -> uuid.UUID:
    row = db.exec(select(User).where(User.username == username)).first()
    assert row is not None
    return row.id  # type: ignore[return-value]


def _make_question(
    db: Session,
    *,
    parent_id: uuid.UUID,
    stem: str,
    subject: str = "数学",
    options: list[str] | None = None,
    qtype: str = "calc",
) -> Question:
    q = Question(
        parent_id=parent_id,
        subject=subject,
        grade=2,
        knowledge_point="加法",
        qtype=qtype,
        stem=stem,
        options=options,
        answer="答案不应出现在纸上",
        explanation="解析也不应出现在纸上",
    )
    db.add(q)
    db.commit()
    db.refresh(q)
    return q


@pytest.fixture()
def two_parents(client, db):
    # db 夹具是 session 级：用户名必须逐测试唯一，否则第二个测试撞「用户名已存在」400
    p1, p2 = f"exp_{uuid.uuid4().hex[:8]}", f"exp_{uuid.uuid4().hex[:8]}"
    assert register_parent(client, username=p1).status_code == 200
    assert register_parent(client, username=p2).status_code == 200
    token1 = login(client, p1, "pw123456").json()["access_token"]
    token2 = login(client, p2, "pw123456").json()["access_token"]
    return (token1, token2, _parent_id(db, p1), _parent_id(db, p2))


def test_export_bank_returns_pdf(client, db, two_parents):
    token1, _, parent1_id, _ = two_parents
    questions = [
        _make_question(db, parent_id=parent1_id, stem=f"计算 {i} + {i}", qtype="calc")
        for i in range(3)
    ]
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(token1),
        json={"source": "bank", "ids": [str(q.id) for q in questions]},
    )
    assert r.status_code == 200, r.text
    assert r.headers["content-type"] == "application/pdf"
    assert r.content.startswith(b"%PDF-")
    assert len(r.content) > 1000


def test_export_bank_rejects_foreign_question(client, db, two_parents):
    token1, _, _, parent2_id = two_parents
    foreign = _make_question(db, parent_id=parent2_id, stem="别人家的题")
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(token1),
        json={"source": "bank", "ids": [str(foreign.id)]},
    )
    assert r.status_code == 403
    # 越权响应里不得泄露题目内容
    assert "别人家的题" not in r.text


def test_export_bank_requires_ids(client, two_parents):
    token1 = two_parents[0]
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(token1),
        json={"source": "bank", "ids": []},
    )
    assert r.status_code == 400
    assert r.json()["code"] == "EXPORT_80003"


def test_export_hard_limit_returns_clear_error(client, db, two_parents, monkeypatch):
    token1, _, parent1_id, _ = two_parents
    questions = [
        _make_question(db, parent_id=parent1_id, stem=f"限流 {i}") for i in range(3)
    ]
    monkeypatch.setattr(settings, "EXPORT_MAX_QUESTIONS", 2)
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(token1),
        json={"source": "bank", "ids": [str(q.id) for q in questions]},
    )
    assert r.status_code == 400
    assert r.json()["code"] == "EXPORT_80001"
    assert "分批" in r.json()["message"]


def test_export_font_missing_returns_503(client, db, two_parents, monkeypatch):
    token1, _, parent1_id, _ = two_parents
    q = _make_question(db, parent_id=parent1_id, stem="字体缺失也要明确报错")
    monkeypatch.setattr(settings, "EXPORT_FONT_DIR", "/nonexistent-font-dir")
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(token1),
        json={"source": "bank", "ids": [str(q.id)]},
    )
    assert r.status_code == 503
    assert r.json()["code"] == "EXPORT_80002"


def test_export_unknown_source_rejected(client, two_parents):
    token1 = two_parents[0]
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(token1),
        json={"source": "web", "ids": []},
    )
    # source 是 Literal 枚举：未知来源在请求校验层就被拒（422），到不了业务层
    assert r.status_code == 422


def test_export_wrong_book_requires_child(client, two_parents):
    token1 = two_parents[0]
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(token1),
        json={"source": "wrong_book"},
    )
    assert r.status_code == 400
    assert r.json()["code"] == "EXPORT_80005"


def _register_child(client, db: Session, token: str) -> tuple[uuid.UUID, str]:
    """在自家名下建一个娃娃账号并返回 ``(child_id, 娃娃自己的 token)``。"""
    username = f"kid_{uuid.uuid4().hex[:8]}"
    r = client.post(
        "/api/v1/children",
        headers=auth_headers(token),
        json={
            "username": username,
            "password": "kid123456",
            "display_name": "导出测试娃",
            "grade": 2,
            "role": "child",
        },
    )
    assert r.status_code == 201, r.text
    row = db.exec(select(User).where(User.username == username)).first()
    assert row is not None
    kid_token = login(client, username, "kid123456").json()["access_token"]
    return row.id, kid_token  # type: ignore[return-value]


def _add_wrong_question(
    db: Session, *, child_id: uuid.UUID, question_id: uuid.UUID, due_at
) -> None:
    from app.db.models import WrongQuestion

    db.add(
        WrongQuestion(
            child_id=child_id,
            question_id=question_id,
            due_at=due_at,
            first_wrong_at=due_at,
        )
    )
    db.commit()


def test_export_wrong_book_foreign_child_rejected(client, db, two_parents):
    _, token2, _, _ = two_parents
    foreign_child_id = uuid.uuid4()
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(token2),
        json={"source": "wrong_book", "child_id": str(foreign_child_id)},
    )
    assert r.status_code == 403


def test_child_can_export_own_due_reviews(client, db, two_parents):
    """复习页 WYSIWYG：娃娃导出的就是他屏幕上到期的那些题。"""
    from datetime import UTC, datetime

    token1, _, parent1_id, _ = two_parents
    child_id, kid_token = _register_child(client, db, token1)
    q = _make_question(db, parent_id=parent1_id, stem="到期错题 1")
    _add_wrong_question(
        db, child_id=child_id, question_id=q.id, due_at=datetime.now(UTC)
    )
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(kid_token),
        json={"source": "wrong_book", "due_only": True},
    )
    assert r.status_code == 200, r.text
    assert r.content.startswith(b"%PDF-")


def test_child_cannot_export_other_sources(client, db, two_parents):
    token1, _, parent1_id, _ = two_parents
    _, kid_token = _register_child(client, db, token1)
    q = _make_question(db, parent_id=parent1_id, stem="娃娃不能碰题库来源")
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(kid_token),
        json={"source": "bank", "ids": [str(q.id)]},
    )
    assert r.status_code == 400
    assert r.json()["code"] == "EXPORT_80006"


def test_child_cannot_export_another_child_book(client, db, two_parents):
    token1, _, _, _ = two_parents
    _, kid_token = _register_child(client, db, token1)
    other_child_id, _ = _register_child(client, db, token1)
    r = client.post(
        "/api/v1/export/sheet",
        headers=auth_headers(kid_token),
        json={"source": "wrong_book", "child_id": str(other_child_id)},
    )
    assert r.status_code == 400
    assert r.json()["code"] == "EXPORT_80006"
