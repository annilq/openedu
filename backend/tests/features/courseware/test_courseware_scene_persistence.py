"""课件环节的场景数据持久化验证（ADR-0076 · ticket 01：证伪票）。

全案（02–05）建立在一条前提上：**环节的 ``scene`` 是裸 dict 透传，后端零改动**——
教师在一个环节里编排的一组图形（``optionGroup``：``curated`` + 有序 ``items``，
条目内 ``points`` 是展开好的二维顶点数组）能原样存进去、原样读回来。

这条结论此前只是读代码得出的，本文件把它钉成端到端断言，打在 REST 接缝上
（ADR-0061 §U.1 教训：只测 service 会漏掉「响应里根本没有这个 key」）。

验的三件事：
1. **写 + 读**：``curated`` / ``items`` 顺序 / ``points`` 顶点都回来，没被剥 key、
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
from app.features.courseware import service
from tests.utils.user import auth_headers, login, register_teacher

KP_NAME = "图形的运动（轴对称）"

# 一组有序图形（课件编排）：顺序即数组顺序，教学意图落在顺序里。
# 刻意排成「非库序、非字母序」——若后端/模型层重排过，顺序断言就会红。
_OPTION_ITEMS = [
    {
        "label": "",
        "caption": "长方形",
        "figureKey": "rectangle",
        "points": [[-80.0, -50.0], [80.0, -50.0], [80.0, 50.0], [-80.0, 50.0]],
        "defaultAxisAngle": 0,
    },
    {
        "label": "",
        "caption": "正方形",
        "figureKey": "square",
        "points": [[-60.0, -60.0], [60.0, -60.0], [60.0, 60.0], [-60.0, 60.0]],
        "defaultAxisAngle": 90,
    },
    {
        "label": "",
        "caption": "箭头",
        "figureKey": "arrow",
        "points": [
            [-40.0, 0.0],
            [10.0, 0.0],
            [10.0, -40.0],
            [60.0, 40.0],
            [10.0, 120.0],
            [10.0, 80.0],
            [-40.0, 80.0],
        ],
        "defaultAxisAngle": 45,
    },
]

_SCENE_WITH_GROUP = {
    "kind": "reflection",
    "title": "哪些对折后能重合",
    "optionGroup": {
        "curated": True,
        "items": _OPTION_ITEMS,
    },
}

_KP_SCENE = {"kind": "reflection", "title": "知识点默认讲解", "inputs": []}


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


@pytest.fixture()
def drafted(monkeypatch):
    """起草环节可用：返回确定性单环节（本票不关心起草内容，只借它建课件）。"""

    def _fake(**_kwargs):
        return [
            service.CoursewareSection(
                kind="interactive_scene",
                title="判断是否轴对称",
                script="沿这条线对折，两边能重合吗？",
                payload={"kind": "reflection"},
            )
        ]

    monkeypatch.setattr(service, "draft_sections", _fake)


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


def test_option_group_survives_put_then_get(client, teacher, drafted):
    """带 ``optionGroup`` 的环节：保存成功，回读后 curated / 条目顺序 / 顶点全在。"""
    cw = _create(client, teacher["token"], teacher["kp"])

    r = _put_sections(
        client, teacher["token"], cw["id"], [_section_body(_SCENE_WITH_GROUP)]
    )
    assert r.status_code == 200, r.text

    saved = r.json()["sections"][0]["scene"]
    assert saved["optionGroup"]["curated"] is True
    assert len(saved["optionGroup"]["items"]) == len(_OPTION_ITEMS)

    body = _get(client, teacher["token"], cw["id"])
    scene = body["sections"][0]["scene"]
    assert scene is not None, "回读时场景丢了"

    group = scene["optionGroup"]
    assert group["curated"] is True, "curated 开关被剥掉了"

    items = group["items"]
    assert [it["figureKey"] for it in items] == [
        it["figureKey"] for it in _OPTION_ITEMS
    ], "条目顺序被重排过（教学编排意图就落在顺序里）"
    assert len(items) == len(_OPTION_ITEMS)

    for got, want in zip(items, _OPTION_ITEMS):
        assert got["label"] == want["label"] == ""
        assert got["caption"] == want["caption"]
        assert got["defaultAxisAngle"] == want["defaultAxisAngle"]
        # points 必须是二维顶点数组：非空、没被压平成字符串、每个顶点仍是 [x, y]
        points = got["points"]
        assert isinstance(points, list), f"points 被改写成了 {type(points)}"
        assert points, "points 空了"
        assert len(points) == len(want["points"])
        for vertex in points:
            assert isinstance(vertex, list), f"顶点被压平了：{vertex!r}"
            assert len(vertex) == 2
        assert points == want["points"]


# ── 2. 反向语义：显式清空不被吞 ──────────────────────────────────────────


def test_explicit_null_scene_is_not_swallowed(client, teacher, drafted):
    """先存一组图形，再显式 ``scene: null`` 保存 → 回读确实是 null。

    ``??`` 合并会把「显式清空」当成「没传」而保留旧值，导致删掉图形组时删不掉。
    """
    cw = _create(client, teacher["token"], teacher["kp"])

    r = _put_sections(
        client, teacher["token"], cw["id"], [_section_body(_SCENE_WITH_GROUP)]
    )
    assert r.status_code == 200, r.text
    assert r.json()["sections"][0]["scene"]["optionGroup"]["items"], "前置：先有图形组"

    r = _put_sections(client, teacher["token"], cw["id"], [_section_body(None)])
    assert r.status_code == 200, r.text
    assert r.json()["sections"][0]["scene"] is None

    body = _get(client, teacher["token"], cw["id"])
    assert body["sections"][0]["scene"] is None, "显式清空被吞了（旧值被保留）"


# ── 3. 不回写：动的是环节副本 ────────────────────────────────────────────


def test_saving_section_scene_does_not_write_back_to_kp(client, teacher, drafted):
    """保存环节场景后，知识点上的场景快照前后一致（ADR-0073 零回写红线）。"""
    before = _kp_scenes(teacher["kp"])
    assert before == [_KP_SCENE]

    cw = _create(client, teacher["token"], teacher["kp"])
    r = _put_sections(
        client, teacher["token"], cw["id"], [_section_body(_SCENE_WITH_GROUP)]
    )
    assert r.status_code == 200, r.text

    assert _kp_scenes(teacher["kp"]) == before
