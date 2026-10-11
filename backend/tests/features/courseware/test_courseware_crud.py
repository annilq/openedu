"""课件端点（ADR-0067 切片 3）：快照 / 越权 / 环节内容块容器 / 孤儿课件 / 状态不阻塞。

全部打在 REST 端点上验（ADR-0061 §U.1 教训：只测 service 会漏掉响应里根本没有
的 key）。ADR-0085 后课件由教师**手动编辑**：新建只产**零环节空壳**，内容经
``PUT /sections`` 整体覆盖写——本套件因此不涉及任何模型调用，也不再需要起草桩。

覆盖的边界：
1. 建课件把知识点的范围与名字**快照**进课件行（展示不 join），且建出的是空壳；
2. 列表按范围过滤 + 别人的课件读不到（归属只经 ``core.guard``）；
3. ``PUT /sections`` 整体覆盖写；旧 kind 字段被忽略（不回显）；清空落真 SQL NULL；
4. 知识点被删后课件**存活**且 ``kp_missing=True``（§4.1）；
5. draft / ready 都不阻塞任何读操作（§3.2）；
6. AI 起草端点（``POST /redraft``）已移除（ADR-0085）。
"""

from __future__ import annotations

import json
import uuid

import pytest
from sqlalchemy import text
from sqlmodel import Session as DBSession
from sqlmodel import select

from app.core.db import engine
from app.core.errors import ErrCode
from app.db.models import Courseware, KnowledgePoint, User
from tests.utils.user import auth_headers, login, register_teacher

KP_NAME = "图形的运动（轴对称）"


def _seed_kp(
    *,
    teacher_id: uuid.UUID,
    name: str = KP_NAME,
    subject: str = "数学",
    grade: int = 4,
    semester: str = "上学期",
) -> uuid.UUID:
    with DBSession(engine) as s:
        kp = KnowledgePoint(
            teacher_id=teacher_id,
            subject=subject,
            grade=grade,
            semester=semester,
            name=name,
        )
        s.add(kp)
        s.commit()
        s.refresh(kp)
        return kp.id


def _delete_kp(kp_id: uuid.UUID) -> None:
    """模拟 ADR-0064 的孤儿知识点清理——课件不级联删除，只能靠快照存活。"""
    with DBSession(engine) as s:
        kp = s.get(KnowledgePoint, kp_id)
        if kp is not None:
            s.delete(kp)
            s.commit()


@pytest.fixture()
def teacher(client):
    """教师账号 + token + 一个知识点。"""
    username = f"cw_{uuid.uuid4().hex[:8]}"
    register_teacher(client, username=username)
    token = login(client, username, "pw123456").json()["access_token"]
    with DBSession(engine) as s:
        user = s.exec(select(User).where(User.username == username)).one()
        teacher_id = user.id
    return {"token": token, "id": teacher_id, "kp": _seed_kp(teacher_id=teacher_id)}


def _create(client, token, kp_id, *, title=None, objective=None):
    """新建课件（ADR-0085 后恒为**零环节空壳**，不调模型）。"""
    payload: dict = {"knowledge_point_id": str(kp_id)}
    if title is not None:
        payload["title"] = title
    if objective is not None:
        payload["objective"] = objective
    return client.post("/api/v1/courseware", headers=auth_headers(token), json=payload)


def _put_sections(client, token, cw_id, sections):
    return client.put(
        f"/api/v1/courseware/{cw_id}/sections",
        headers=auth_headers(token),
        json={"sections": sections},
    )


def test_create_snapshots_knowledge_point_scope(client, teacher):
    """建课件：范围与知识点名从知识点行**快照**进课件行（§3.2 展示不 join）。"""
    r = _create(client, teacher["token"], teacher["kp"])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["kp_name"] == KP_NAME
    assert body["subject"] == "数学"
    assert body["grade"] == 4
    assert body["semester"] == "上学期"
    assert body["knowledge_point_id"] == str(teacher["kp"])
    assert body["kp_missing"] is False
    # ADR-0085：新建只产零环节空壳，内容由教师手动添加。
    assert body["section_count"] == 0 and body["sections"] == []

    # 库里确实是快照，不是 join 出来的；空壳的 sections 是 NULL（不是空列表）。
    with DBSession(engine) as s:
        row = s.get(Courseware, uuid.UUID(body["id"]))
        assert row.kp_name == KP_NAME and row.subject == "数学"
        assert row.sections is None


def test_create_persists_objective_without_calling_model(client, teacher):
    """教学目标 / 备注落到课件行；新建不调模型——没有「未配模型」这一失败面（ADR-0085）。"""
    r = _create(client, teacher["token"], teacher["kp"], objective="能画出对称轴")
    assert r.status_code == 200, r.text
    with DBSession(engine) as s:
        row = s.get(Courseware, uuid.UUID(r.json()["id"]))
        assert row.objective == "能画出对称轴"


def test_create_with_unknown_knowledge_point_is_404(client, teacher):
    """知识点不存在 → ``COURSEWARE_KP_NOT_FOUND``，且不落库。"""
    r = _create(client, teacher["token"], uuid.uuid4())
    assert r.status_code == 404, r.text
    assert r.json()["code"] == ErrCode.COURSEWARE_KP_NOT_FOUND.value
    listing = client.get("/api/v1/courseware", headers=auth_headers(teacher["token"]))
    assert listing.json() == []


def test_list_filters_by_scope_and_hides_other_teachers(client, teacher):
    """列表按范围过滤；别人的课件读不到（越权 404，不降级成 200 空）。"""
    other_user = f"cw_{uuid.uuid4().hex[:8]}"
    register_teacher(client, username=other_user)
    other_token = login(client, other_user, "pw123456").json()["access_token"]

    mine = _create(client, teacher["token"], teacher["kp"]).json()
    # 同学科不同年级的另一份
    kp2 = _seed_kp(teacher_id=teacher["id"], name="分数的初步认识", grade=5)
    other_grade = _create(client, teacher["token"], kp2).json()

    all_rows = client.get(
        "/api/v1/courseware", headers=auth_headers(teacher["token"])
    ).json()
    assert {r["id"] for r in all_rows} == {mine["id"], other_grade["id"]}
    # 顺序：最近更新在前
    assert all_rows[0]["id"] == other_grade["id"]

    by_grade = client.get(
        "/api/v1/courseware?grade=4", headers=auth_headers(teacher["token"])
    ).json()
    assert [r["id"] for r in by_grade] == [mine["id"]]

    by_subject = client.get(
        "/api/v1/courseware?subject=数学&semester=上学期&grade=5",
        headers=auth_headers(teacher["token"]),
    ).json()
    assert [r["id"] for r in by_subject] == [other_grade["id"]]

    by_kp = client.get(
        f"/api/v1/courseware?knowledge_point_id={teacher['kp']}",
        headers=auth_headers(teacher["token"]),
    ).json()
    assert [r["id"] for r in by_kp] == [mine["id"]]

    # 别人的课件：列表里没有、直取 404
    assert client.get("/api/v1/courseware", headers=auth_headers(other_token)).json() == []
    denied = client.get(
        f"/api/v1/courseware/{mine['id']}", headers=auth_headers(other_token)
    )
    assert denied.status_code == 404, denied.text
    assert denied.json()["code"] == ErrCode.COURSEWARE_NOT_FOUND.value


def test_replace_sections_ignores_legacy_kind_field(client, teacher):
    """``PUT /sections`` 整体覆盖写；T07 后环节无 kind 字段，旧 kind 输入被忽略且不回显。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    url = f"/api/v1/courseware/{cw['id']}/sections"

    payload = {
        "sections": [
            {
                "id": "a",
                "title": "练习",
                "script": "这几题你会吗？",
                "payload": {"qtype": "choice", "count": 2},
            },
            {
                "id": "b",
                "title": "判定",
                "script": "拖动对称轴试试",
                "payload": {"kind": "reflection"},
            },
        ]
    }
    r = client.put(url, headers=auth_headers(teacher["token"]), json=payload)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["section_count"] == 2
    assert [s["id"] for s in body["sections"]] == ["a", "b"]
    assert all("kind" not in s for s in body["sections"])

    # 覆盖写：再提交一份只留最后一个环节
    r = client.put(
        url,
        headers=auth_headers(teacher["token"]),
        json={"sections": [payload["sections"][1]]},
    )
    assert r.status_code == 200, r.text
    assert r.json()["section_count"] == 1
    assert r.json()["sections"][0]["id"] == "b"

    # T07 去 kind·contract：环节无 kind 字段，旧 kind 输入被忽略、PUT 成功且原内容不动。
    bad = client.put(
        url,
        headers=auth_headers(teacher["token"]),
        json={"sections": [{"title": "视频"}]},
    )
    assert bad.status_code == 200, bad.text
    after = client.get(
        f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
    ).json()
    assert after["section_count"] == 1
    assert "kind" not in after["sections"][0]


def test_replace_sections_roundtrips_script_segments(client, teacher):
    """PUT /sections 透传话术多段 + 重点（T02），GET 原样回；旧单串 script 仍兼容。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    url = f"/api/v1/courseware/{cw['id']}/sections"
    payload = {
        "sections": [
            {
                "id": "a",
                "title": "观察",
                "script": "这些图形有什么共同点？",
                "script_segments": [
                    {"text": "开场：看图", "emphasis": "bold"},
                    {"text": "追问：共同点？", "emphasis": "highlight"},
                    {"text": "收尾：小结", "emphasis": "none"},
                ],
                "payload": {"items": []},
            }
        ]
    }
    r = client.put(url, headers=auth_headers(teacher["token"]), json=payload)
    assert r.status_code == 200, r.text
    body = r.json()
    seg = body["sections"][0]["script_segments"]
    assert [s["text"] for s in seg] == ["开场：看图", "追问：共同点？", "收尾：小结"]
    assert [s["emphasis"] for s in seg] == ["bold", "highlight", "none"]
    # 旧的单串 script 仍原样下发（向后兼容首轮单串课件）。
    assert body["sections"][0]["script"] == "这些图形有什么共同点？"

    # 重读仍保持段列表。
    got = client.get(
        f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
    ).json()
    assert got["sections"][0]["script_segments"] == seg


def test_clearing_sections_writes_sql_null(client, teacher):
    """清空环节写的是**真 SQL NULL**，不是文本 ``'null'``（§3.2 none_as_null）。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    url = f"/api/v1/courseware/{cw['id']}/sections"
    r = client.put(url, headers=auth_headers(teacher["token"]), json={"sections": []})
    assert r.status_code == 200, r.text
    assert r.json()["section_count"] == 0 and r.json()["sections"] == []

    with DBSession(engine) as s:
        # UUID 列在 SQLite 里存的是 CHAR(32)（无连字符的 hex），直接比字符串会落空
        got = s.exec(
            text("SELECT typeof(sections) FROM courseware WHERE id = :cid"),
            params={"cid": uuid.UUID(cw["id"]).hex},
        ).one()
    assert got[0] == "null"


def test_legacy_kind_in_stored_sections_is_ignored(client, teacher):
    """T07 回归：历史课件 JSON 里带 kind 键仍能读取并演示（kind 被忽略，不破坏数据）。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    cw_id = uuid.UUID(cw["id"])
    # 直接往库里写一份带 legacy kind 的环节 JSON（模拟 T07 之前的老数据）。
    with DBSession(engine) as s:
        s.exec(
            text("UPDATE courseware SET sections = :secs WHERE id = :cid"),
            params={
                "secs": json.dumps(
                    [
                        {
                            "id": "old1",
                            "kind": "media_gallery",
                            "title": "老环节",
                            "script": "老话术",
                            "materials": [],
                        }
                    ]
                ),
                "cid": cw_id.hex,
            },
        )
        s.commit()

    got = client.get(
        f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
    )
    assert got.status_code == 200, got.text
    body = got.json()
    assert body["section_count"] == 1
    sec = body["sections"][0]
    # kind 键被忽略、不回显；其余内容照常读取。
    assert "kind" not in sec
    assert sec["title"] == "老环节"
    assert sec["script"] == "老话术"


def test_courseware_survives_knowledge_point_deletion(client, teacher):
    """知识点被 ADR-0064 清理后课件**存活**，``kp_missing=True``（§4.1）。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    _put_sections(
        client,
        teacher["token"],
        cw["id"],
        [
            {"title": "生活中的对称", "script": "这些图形有什么共同点？"},
            {"title": "课堂练习", "script": "下面哪些图形是轴对称图形？"},
        ],
    )
    _delete_kp(teacher["kp"])

    got = client.get(
        f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
    )
    assert got.status_code == 200, got.text
    body = got.json()
    assert body["kp_missing"] is True
    # 展示靠快照：名字还在，环节还在
    assert body["kp_name"] == KP_NAME
    assert body["section_count"] == 2

    listed = client.get(
        "/api/v1/courseware", headers=auth_headers(teacher["token"])
    ).json()
    assert [r["kp_missing"] for r in listed] == [True]


def test_status_never_blocks_reads(client, teacher):
    """draft / ready 都不阻塞任何读操作——状态只是列表标签（§3.2）。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    assert cw["status"] == "draft"
    url = f"/api/v1/courseware/{cw['id']}"

    for status in ("ready", "draft"):
        patched = client.patch(
            url,
            headers=auth_headers(teacher["token"]),
            json={"status": status, "title": f"标题-{status}"},
        )
        assert patched.status_code == 200, patched.text
        assert patched.json()["status"] == status
        # 读 / 覆盖写 / 最近课件 全部照常
        assert client.get(url, headers=auth_headers(teacher["token"])).status_code == 200
        assert (
            client.put(
                f"{url}/sections",
                headers=auth_headers(teacher["token"]),
                json={"sections": [{"title": "练", "script": "?"}]},
            ).status_code
            == 200
        )
        recent = client.get(
            "/api/v1/courseware/recent", headers=auth_headers(teacher["token"])
        )
        assert recent.status_code == 200
        assert recent.json()["id"] == cw["id"]


def test_recent_is_null_when_no_courseware(client, teacher):
    """「最近课件」回执：没有课件返回 null（不是 404），由页面决定空态。"""
    r = client.get("/api/v1/courseware/recent", headers=auth_headers(teacher["token"]))
    assert r.status_code == 200, r.text
    assert r.json() is None


def test_recent_follows_latest_update(client, teacher):
    """回执指向**最近更新**的那份（改过标题也要顶上来）。"""
    first = _create(client, teacher["token"], teacher["kp"]).json()
    kp2 = _seed_kp(teacher_id=teacher["id"], name="分数的初步认识", grade=5)
    second = _create(client, teacher["token"], kp2).json()
    r = client.get("/api/v1/courseware/recent", headers=auth_headers(teacher["token"]))
    assert r.json()["id"] == second["id"]

    client.patch(
        f"/api/v1/courseware/{first['id']}",
        headers=auth_headers(teacher["token"]),
        json={"title": "待会儿就用这份"},
    )
    r = client.get("/api/v1/courseware/recent", headers=auth_headers(teacher["token"]))
    assert r.json()["id"] == first["id"]


def test_delete_courseware(client, teacher):
    """删课件：再取 404。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    r = client.delete(
        f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
    )
    assert r.status_code == 200 and r.json() == {"deleted": True}
    assert (
        client.get(
            f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
        ).status_code
        == 404
    )


def test_redraft_endpoint_is_gone(client, teacher):
    """ADR-0085：AI 起草端点已移除——不再提供逐段重起草（``POST /redraft`` → 404）。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    r = client.post(
        f"/api/v1/courseware/{cw['id']}/redraft",
        headers=auth_headers(teacher["token"]),
    )
    assert r.status_code == 404, r.text


# ── 环节场景：统一解析入口（ADR-0073） ─────────────────────────────────


_REFLECTION_SCENE = {
    "kind": "reflection",
    "title": "轴对称",
    "inputs": [{"key": "figure", "value": "square"}],
    "editable": True,
}


def _set_kp_scenes(kp_id: uuid.UUID, scenes: list[dict] | None) -> None:
    with DBSession(engine) as s:
        kp = s.get(KnowledgePoint, kp_id)
        kp.scenes = scenes
        s.add(kp)
        s.commit()


def test_teacher_can_clear_scene_without_it_being_refilled(client, teacher):
    """教师显式发送 ``scene=None`` 保存 → 落库为 None，不被任何逻辑回填。

    课件从不在保存路径注入场景：教师「清除场景」按钮（发 ``null``）会真正生效，
    演示页随后回落到「未配置交互演示」空态。
    """
    _set_kp_scenes(teacher["kp"], [_REFLECTION_SCENE])
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    url = f"/api/v1/courseware/{cw['id']}/sections"

    r = client.put(
        url,
        headers=auth_headers(teacher["token"]),
        json={
            "sections": [
                {
                    "id": "only",
                    "title": "判定",
                    "script": "拖动对称轴试试",
                    "payload": {"kind": "reflection"},
                    "scene": None,
                }
            ]
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["sections"][0]["scene"] is None

    body = client.get(
        f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
    ).json()
    assert body["sections"][0]["scene"] is None
