"""课件环节的场景数据持久化验证（ADR-0076 · ticket 01：证伪票；ADR-0091 ticket 02 改形）。

全案（02–05）建立在一条前提上：**环节的 ``scene`` 是裸 dict 透传，后端零改动**——
教师在一个环节里编排的一组图形（ADR-0091 起：顶层 ``options`` 图形数组 + ``curated``，
条目即 ``{key,label,points,edges}`` 的 Figure）能原样存进去、原样读回来。

这条结论此前只是读代码得出的，本文件把它钉成端到端断言，打在 REST 接缝上
（ADR-0061 §U.1 教训：只测 service 会漏掉「响应里根本没有这个 key」）。

验的三件事：
1. **写 + 读**：``curated`` / 图形顺序 / ``points`` 顶点都回来，没被剥 key、
   没被压平成字符串；
2. **反向语义**：显式 ``scene: null`` 保存后回读确实是 null（哨兵语义没被 ``??`` 吞）；
3. **不回写**：动的是环节副本，知识点上的场景快照前后一致（ADR-0073 零回写红线）。

本文件**只验证不做功能**：不引入编辑器 UI、不改渲染层、不改后端 schema/service。
"""

from __future__ import annotations

import uuid

import pytest
from sqlmodel import Session as DBSession
from sqlmodel import select

from app.core.db import engine
from app.db.models import KnowledgePoint, User
from tests.utils.user import auth_headers, login, register_teacher

KP_NAME = "图形的运动（轴对称）"

# 一组有序图形（课件编排）：顺序即数组顺序，教学意图落在顺序里。
# 刻意排成「非库序、非字母序」——若后端/模型层重排过，顺序断言就会红。
# ADR-0091 起条目即 Figure：{key, label, points, edges}（key 是图库身份键）。
_OPTION_FIGURES = [
    {
        "key": "rectangle",
        "label": "长方形",
        "points": [[-80.0, -50.0], [80.0, -50.0], [80.0, 50.0], [-80.0, 50.0]],
        "edges": [[0, 1], [1, 2], [2, 3], [3, 0]],
    },
    {
        "key": "square",
        "label": "正方形",
        "points": [[-60.0, -60.0], [60.0, -60.0], [60.0, 60.0], [-60.0, 60.0]],
        "edges": [[0, 1], [1, 2], [2, 3], [3, 0]],
    },
    {
        "key": "arrow",
        "label": "箭头",
        "points": [
            [-40.0, 0.0],
            [10.0, 0.0],
            [10.0, -40.0],
            [60.0, 40.0],
            [10.0, 120.0],
            [10.0, 80.0],
            [-40.0, 80.0],
        ],
        "edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 0]],
    },
]

_SCENE_WITH_OPTIONS = {
    "kind": "reflection",
    "options": _OPTION_FIGURES,
    "curated": True,
}

_KP_SCENE = {
    "kind": "reflection",
    "figure": {
        "key": "house",
        "label": "房子",
        "points": [[0.30, 0.70], [0.70, 0.70], [0.70, 0.45], [0.50, 0.25], [0.30, 0.45]],
        "edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]],
    },
}


def _seed_kp(teacher_id: uuid.UUID) -> uuid.UUID:
    with DBSession(engine) as s:
        kp = KnowledgePoint(
            teacher_id=teacher_id,
            subject="数学",
            grade=4,
            semester="上学期",
            name=KP_NAME,
            scenes=[_KP_SCENE],
        )
        s.add(kp)
        s.commit()
        s.refresh(kp)
        return kp.id


def _kp_scenes(kp_id: uuid.UUID) -> list:
    with DBSession(engine) as s:
        kp = s.get(KnowledgePoint, kp_id)
        return kp.scenes


@pytest.fixture()
def teacher(client):
    """教师账号 + token + 一个已配默认场景的知识点。"""
    username = f"cwscene_{uuid.uuid4().hex[:8]}"
    register_teacher(client, username=username)
    token = login(client, username, "pw123456").json()["access_token"]
    with DBSession(engine) as s:
        user = s.exec(select(User).where(User.username == username)).one()
        teacher_id = user.id
    return {"token": token, "id": teacher_id, "kp": _seed_kp(teacher_id)}


def _create(client, token, kp_id) -> dict:
    r = client.post(
        "/api/v1/courseware",
        headers=auth_headers(token),
        json={"knowledge_point_id": str(kp_id)},
    )
    assert r.status_code == 200, r.text
    return r.json()


def _put_sections(client, token, cw_id, sections):
    return client.put(
        f"/api/v1/courseware/{cw_id}/sections",
        headers=auth_headers(token),
        json={"sections": sections},
    )


def _get(client, token, cw_id) -> dict:
    r = client.get(f"/api/v1/courseware/{cw_id}", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return r.json()


def _section_body(scene) -> dict:
    return {
        "id": "only",
        "kind": "interactive_scene",
        "title": "一组图形",
        "script": "这些图形有什么共同点？",
        "payload": {"kind": "reflection"},
        "scene": scene,
    }


# ── 1. 写 + 读：整组图形原样回来 ──────────────────────────────────────────


def test_options_group_survives_put_then_get(client, teacher):
    """带 ``options`` 图形组的环节：保存成功，回读后 curated / 图形顺序 / 顶点全在。"""
    cw = _create(client, teacher["token"], teacher["kp"])

    r = _put_sections(
        client, teacher["token"], cw["id"], [_section_body(_SCENE_WITH_OPTIONS)]
    )
    assert r.status_code == 200, r.text

    saved = r.json()["sections"][0]["scene"]
    assert saved["curated"] is True
    assert len(saved["options"]) == len(_OPTION_FIGURES)

    body = _get(client, teacher["token"], cw["id"])
    scene = body["sections"][0]["scene"]
    assert scene is not None, "回读时场景丢了"

    assert scene["curated"] is True, "curated 开关被剥掉了"

    figures = scene["options"]
    assert [it["key"] for it in figures] == [
        it["key"] for it in _OPTION_FIGURES
    ], "图形顺序被重排过（教学编排意图就落在顺序里）"
    assert len(figures) == len(_OPTION_FIGURES)

    for got, want in zip(figures, _OPTION_FIGURES):
        assert got["key"] == want["key"]
        assert got["label"] == want["label"]
        # points 必须是二维顶点数组：非空、没被压平成字符串、每个顶点仍是 [x, y]
        points = got["points"]
        assert isinstance(points, list), f"points 被改写成了 {type(points)}"
        assert points, "points 空了"
        assert len(points) == len(want["points"])
        for vertex in points:
            assert isinstance(vertex, list), f"顶点被压平了：{vertex!r}"
            assert len(vertex) == 2
        assert points == want["points"]
        assert got["edges"] == want["edges"]


# ── 2. 反向语义：显式清空不被吞 ──────────────────────────────────────────


def test_explicit_null_scene_is_not_swallowed(client, teacher):
    """先存一组图形，再显式 ``scene: null`` 保存 → 回读确实是 null。

    ``??`` 合并会把「显式清空」当成「没传」而保留旧值，导致删掉图形组时删不掉。
    """
    cw = _create(client, teacher["token"], teacher["kp"])

    r = _put_sections(
        client, teacher["token"], cw["id"], [_section_body(_SCENE_WITH_OPTIONS)]
    )
    assert r.status_code == 200, r.text
    assert r.json()["sections"][0]["scene"]["options"], "前置：先有图形组"

    r = _put_sections(client, teacher["token"], cw["id"], [_section_body(None)])
    assert r.status_code == 200, r.text
    assert r.json()["sections"][0]["scene"] is None

    body = _get(client, teacher["token"], cw["id"])
    assert body["sections"][0]["scene"] is None, "显式清空被吞了（旧值被保留）"


# ── 3. 不回写：动的是环节副本 ────────────────────────────────────────────


def test_saving_section_scene_does_not_write_back_to_kp(client, teacher):
    """保存环节场景后，知识点上的场景快照前后一致（ADR-0073 零回写红线）。"""
    before = _kp_scenes(teacher["kp"])
    assert before == [_KP_SCENE]

    cw = _create(client, teacher["token"], teacher["kp"])
    r = _put_sections(
        client, teacher["token"], cw["id"], [_section_body(_SCENE_WITH_OPTIONS)]
    )
    assert r.status_code == 200, r.text

    assert _kp_scenes(teacher["kp"]) == before
