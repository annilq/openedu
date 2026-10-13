"""选项内嵌图形（ADR-0089 决策 2 / ticket 02）——端点级契约测试。

历史教训：只测服务会漏掉「某个端点整段忘了下发」——形状类断言一律走**端点级**。
因此这里全部经真实 HTTP：

- `POST /tasks/from-generated` 落库：模型只给**图形身份键**，后端按图库**盖几何章**；
- `GET /tasks/{id}` 下发 `options[].figure`（**几何内联**，渲染零图库依赖）。

钉住的行为：
1. 合法身份键 → 每个选项带内联几何（顶点来自图库，不在响应里回查）；
2. **全-or-无**：部分选项没图 / 未知键 → 整题退化纯文字（不是半套图）；
3. **快照不可变**：改图库顶点后，已落库的选项几何**不变**；
4. `text` 恒存在且**保留前缀**（"A."）——判题与无障碍的依据；
5. 选项图形**不带 `kind`**（演示类型取题目级场景规格）。
"""
from __future__ import annotations

import uuid

from sqlmodel import Session, select

from app.core.db import engine
from app.db.models import FigureLibrary
from tests.utils.user import auth_headers, register_teacher

_SUBJECT = "数学"
_GRADE = 4
_KP = "图形的运动（轴对称）"

# 一个自定义三角形（不是内置预设）——快照不可变性用它验证。
_USER_POINTS = [[0.20, 0.80], [0.80, 0.80], [0.50, 0.30]]
_USER_EDGES = [[0, 1], [1, 2], [2, 0]]


def _teacher(client, username) -> str:
    return register_teacher(client, username=username).json()["access_token"]


def _choice_question(options: list[dict]) -> dict:
    return {
        "subject": _SUBJECT,
        "grade": _GRADE,
        "knowledge_point": _KP,
        "qtype": "choice",
        "stem": "下列图形中，哪些是轴对称图形？",
        "options": options,
        "answer": "A. 正方形",
        "explanation": "正方形有四条对称轴。",
        "difficulty": "medium",
        "semester": "",
    }


def _persist(client, token, questions: list[dict]) -> dict:
    r = client.post(
        "/api/v1/tasks/from-generated",
        headers=auth_headers(token),
        json={
            "title": "图形选择题",
            "model": "local-llama",
            "specs": [
                {
                    "subject": _SUBJECT,
                    "grade": _GRADE,
                    "knowledge_point": _KP,
                    "qtype": "choice",
                    "difficulty": "medium",
                    "count": 1,
                }
            ],
            "questions": questions,
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def _task_detail(client, token, task_id: str) -> dict:
    r = client.get(f"/api/v1/tasks/{task_id}", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return r.json()


# ───────────────────── 合法键 → 盖几何章 ─────────────────────


def test_option_figures_stamped_and_emitted_inline(client):
    token = _teacher(client, "ofig_ok")
    body = _persist(
        client,
        token,
        [
            _choice_question(
                [
                    {"text": "A. 正方形", "figure_key": "square"},
                    {"text": "B. 平行四边形", "figure_key": "para"},
                ]
            )
        ],
    )
    q = body["questions"][0]
    opts = q["options"]
    assert [o["text"] for o in opts] == ["A. 正方形", "B. 平行四边形"]

    # 每个选项都带内联几何（顶点 + 连接关系），且来自图库。
    for o in opts:
        fig = o["figure"]
        assert fig is not None
        assert fig["key"] in {"square", "para"}
        assert len(fig["points"]) >= 3
        assert len(fig["edges"]) >= 3
        # 选项图形不带 kind（演示类型取题目级场景规格）。
        assert "kind" not in fig

    # 端点级再拉一次：详情也必须下发同一份几何（历史教训：端点会整段漏写）。
    detail = _task_detail(client, token, body["id"])
    d_opts = detail["questions"][0]["options"]
    assert [o["figure"]["key"] for o in d_opts] == ["square", "para"]


def test_option_figures_geometry_matches_library(client):
    """内联几何必须逐点等于图库（几何单一权威），不是模型给的坐标。"""
    token = _teacher(client, "ofig_geo")
    body = _persist(
        client,
        token,
        [
            _choice_question(
                [
                    {"text": "A. 正方形", "figure_key": "square"},
                    {"text": "B. 平行四边形", "figure_key": "para"},
                ]
            )
        ],
    )
    with Session(engine) as s:
        row = s.exec(
            select(FigureLibrary).where(FigureLibrary.key == "square")
        ).one()
        lib_points = [list(p) for p in row.points or []]
    assert body["questions"][0]["options"][0]["figure"]["points"] == lib_points


# ───────────────────── 全-or-无 ─────────────────────


def test_option_figures_partial_keys_degrades_to_text(client):
    """部分选项没图 → 整题退化纯文字（半套图会把「没图」误导成「不是图形」）。"""
    token = _teacher(client, "ofig_partial")
    body = _persist(
        client,
        token,
        [
            _choice_question(
                [
                    {"text": "A. 正方形", "figure_key": "square"},
                    {"text": "B. 一个普通词", "figure_key": None},
                ]
            )
        ],
    )
    opts = body["questions"][0]["options"]
    assert [o["text"] for o in opts] == ["A. 正方形", "B. 一个普通词"]
    assert all(o["figure"] is None for o in opts)


def test_option_figures_unknown_key_degrades_to_text(client):
    """未知身份键（模型幻觉 / 图库无此行）→ 整题退化，不抛错。"""
    token = _teacher(client, "ofig_unknown")
    body = _persist(
        client,
        token,
        [
            _choice_question(
                [
                    {"text": "A. 正方形", "figure_key": "square"},
                    {"text": "B. 神秘图形", "figure_key": "no_such_figure"},
                ]
            )
        ],
    )
    opts = body["questions"][0]["options"]
    assert all(o["figure"] is None for o in opts)


def test_plain_text_options_have_no_figure(client):
    """没有任何选项引用图形 → 不查目录、不盖章，figure 恒为空。"""
    token = _teacher(client, "ofig_plain")
    body = _persist(
        client,
        token,
        [
            _choice_question(
                [
                    {"text": "A. 1", "figure_key": None},
                    {"text": "B. 2", "figure_key": None},
                ]
            )
        ],
    )
    assert all(o["figure"] is None for o in body["questions"][0]["options"])


# ───────────────────── 快照不可变 ─────────────────────


def test_option_figure_snapshot_is_immutable(client):
    """改图形几何库顶点 → 已落库的选项几何不变（几何在落库时内联成快照）。"""
    key = f"user_{uuid.uuid4().hex[:8]}"
    with Session(engine) as s:
        s.add(
            FigureLibrary(
                key=key,
                label="自绘三角形",
                points=[list(p) for p in _USER_POINTS],
                edges=[list(e) for e in _USER_EDGES],
                is_builtin=False,
            )
        )
        s.commit()
    try:
        token = _teacher(client, "ofig_snapshot")
        body = _persist(
            client,
            token,
            [
                _choice_question(
                    [
                        {"text": "A. 自绘三角形", "figure_key": key},
                        {"text": "B. 正方形", "figure_key": "square"},
                    ]
                )
            ],
        )
        stamped = body["questions"][0]["options"][0]["figure"]["points"]

        # 改图库该行顶点
        with Session(engine) as s:
            row = s.get(FigureLibrary, key)
            row.points = [[0.1, 0.1], [0.9, 0.1], [0.5, 0.9]]
            s.add(row)
            s.commit()

        detail = _task_detail(client, token, body["id"])
        after = detail["questions"][0]["options"][0]["figure"]["points"]
        assert after == stamped, "已落库的选项几何必须冻结（不随图库改动而变）"
        assert after == _USER_POINTS
    finally:
        with Session(engine) as s:
            row = s.get(FigureLibrary, key)
            if row is not None:
                s.delete(row)
                s.commit()


# ───────────────────── 文字与判题 ─────────────────────


def test_option_text_keeps_prefix(client):
    """选项文字保留前缀（判题/展示依赖；前端按位置重画、后端不剥）。"""
    token = _teacher(client, "ofig_text")
    body = _persist(
        client,
        token,
        [
            _choice_question(
                [
                    {"text": "A. 正方形", "figure_key": "square"},
                    {"text": "B. 平行四边形", "figure_key": "para"},
                ]
            )
        ],
    )
    assert body["questions"][0]["options"][0]["text"].startswith("A.")
    assert body["questions"][0]["answer"] == "A. 正方形"


def test_legacy_string_options_tolerated_on_read(client, db):
    """存量旧形（options 是字符串数组）→ 读端点容错包成对象，不 500、无 DDL 迁移。"""
    from app.db.models import Question, User

    token = _teacher(client, "ofig_legacy")
    with Session(engine) as s:
        u = s.exec(select(User).where(User.username == "ofig_legacy")).one()
        s.add(
            Question(
                id=uuid.uuid4(),
                teacher_id=u.id,
                subject=_SUBJECT,
                grade=_GRADE,
                knowledge_point=_KP,
                qtype="choice",
                stem="存量旧形选项",
                options=["A. 正方形", "B. 平行四边形"],  # 旧形：字符串数组
                answer="A. 正方形",
            )
        )
        s.commit()

    r = client.get("/api/v1/questions", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    item = next(i for i in r.json()["items"] if i["stem"] == "存量旧形选项")
    assert [o["text"] for o in item["options"]] == ["A. 正方形", "B. 平行四边形"]
    assert all(o["figure"] is None for o in item["options"])
