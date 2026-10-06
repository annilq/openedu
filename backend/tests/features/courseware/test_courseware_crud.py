"""课件端点（ADR-0067 切片 3）：快照 / 越权 / kind 注册表 / 孤儿课件 / 状态不阻塞。

全部打在 REST 端点上验（ADR-0061 §U.1 教训：只测 service 会漏掉响应里根本没有
的 key）。起草函数一律 monkeypatch 掉——本套件**不打真实模型**。

覆盖的六条边界：
1. 建课件把知识点的范围与名字**快照**进课件行（展示不 join）；
2. 未配模型 → ``LLM_UNAVAILABLE`` 且**不落库**（ADR-0039 / ADR-0066 不伪造）；
3. 列表按范围过滤 + 别人的课件读不到（归属只经 ``core.guard``）；
4. ``PUT /sections`` 整体覆盖写；未知 kind 422；清空落真 SQL NULL；
5. 知识点被删后课件**存活**且 ``kp_missing=True``（§4.1）；
6. draft / ready 都不阻塞任何读操作（§3.2）。
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import text
from sqlmodel import Session as DBSession
from sqlmodel import select

from app.core.db import engine
from app.core.errors import AppErrorException, ErrCode
from app.db.models import Courseware, KnowledgePoint, User
from app.features.courseware import service
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


def _draft() -> list[service.CoursewareSection]:
    """起草替身：确定性三环节，覆盖三种 kind。"""
    return [
        service.CoursewareSection(
            kind="media_gallery",
            title="生活中的对称",
            script="这些图形有什么共同点？",
            payload={"items": [], "prompt": "先找出共同点"},
        ),
        service.CoursewareSection(
            kind="interactive_scene",
            title="判断是否轴对称",
            script="沿这条线对折，两边能重合吗？",
            payload={"kind": "reflection", "title": "轴对称"},
        ),
        service.CoursewareSection(
            kind="practice",
            title="课堂练习",
            script="下面哪些图形是轴对称图形？",
            payload={"qtype": "choice", "count": 3},
        ),
    ]


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


@pytest.fixture()
def no_model(monkeypatch):
    """起草环节不可用：未配置模型（ADR-0039：无离线 mock）。"""

    def _raise(**_kwargs):
        raise AppErrorException(
            ErrCode.LLM_UNAVAILABLE,
            "未配置模型，无法起草课件（请在「模型管理」中添加模型并设为默认）",
        )

    monkeypatch.setattr(service, "draft_sections", _raise)


@pytest.fixture()
def drafted(monkeypatch):
    """起草环节可用：返回确定性三环节，并记录调用参数。"""
    calls: list[dict] = []

    def _fake(**kwargs):
        calls.append(kwargs)
        return _draft()

    monkeypatch.setattr(service, "draft_sections", _fake)
    return calls


def _create(client, token, kp_id):
    return client.post(
        "/api/v1/courseware",
        headers=auth_headers(token),
        json={"knowledge_point_id": str(kp_id)},
    )


def test_create_snapshots_knowledge_point_scope(client, teacher, drafted):
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
    assert body["section_count"] == 3
    assert [s["kind"] for s in body["sections"]] == [
        "media_gallery",
        "interactive_scene",
        "practice",
    ]
    # script 是投给学生看的提问卡（决策 15），必须原样下发
    assert body["sections"][0]["script"] == "这些图形有什么共同点？"
    # 起草拿到了知识点元信息（名称 / 学科 / 年级 / 学期）
    call = drafted[0]
    assert call["kp_name"] == KP_NAME and call["subject"] == "数学"
    assert call["grade"] == 4 and call["semester"] == "上学期"

    # 库里确实是快照，不是 join 出来的
    with DBSession(engine) as s:
        row = s.get(Courseware, uuid.UUID(body["id"]))
        assert row.kp_name == KP_NAME and row.subject == "数学"


def test_create_without_model_real_engine_path(client, teacher):
    """不打起草桩：引擎真的解析不到模型 → ``LLM_UNAVAILABLE``（ADR-0039 无 mock 兜底）。

    上面那条用例打桩只验了「失败不落库」；这条走真实的 ``build_ai_provider``，
    钉住「未配模型」不是靠 service 里的一句 if 演出来的。
    """
    r = _create(client, teacher["token"], teacher["kp"])
    assert r.status_code == 500, r.text
    assert r.json()["code"] == ErrCode.LLM_UNAVAILABLE.value
    assert "未配置模型" in r.json()["message"]


def test_create_without_model_returns_llm_unavailable_and_persists_nothing(
    client, teacher, no_model
):
    """未配模型：500 + ``LLM_UNAVAILABLE``，且**不落库**（不产空课件）。"""
    r = _create(client, teacher["token"], teacher["kp"])
    assert r.status_code == 500, r.text
    assert r.json()["code"] == ErrCode.LLM_UNAVAILABLE.value
    assert "未配置模型" in r.json()["message"]

    listing = client.get("/api/v1/courseware", headers=auth_headers(teacher["token"]))
    assert listing.json() == []
    with DBSession(engine) as s:
        rows = s.exec(
            select(Courseware).where(Courseware.teacher_id == teacher["id"])
        ).all()
    assert rows == []


def test_create_with_unknown_knowledge_point_is_404(client, teacher, drafted):
    """知识点不存在 → ``COURSEWARE_KP_NOT_FOUND``，不进起草。"""
    r = _create(client, teacher["token"], uuid.uuid4())
    assert r.status_code == 404, r.text
    assert r.json()["code"] == ErrCode.COURSEWARE_KP_NOT_FOUND.value
    assert drafted == []


def test_list_filters_by_scope_and_hides_other_teachers(client, teacher, drafted):
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


def test_replace_sections_overwrites_and_rejects_unknown_kind(client, teacher, drafted):
    """``PUT /sections`` 整体覆盖写；未知 kind 422（§3.3 不接受自由字符串）。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    url = f"/api/v1/courseware/{cw['id']}/sections"

    payload = {
        "sections": [
            {
                "id": "a",
                "kind": "practice",
                "title": "练习",
                "script": "这几题你会吗？",
                "payload": {"qtype": "choice", "count": 2},
            },
            {
                "id": "b",
                "kind": "interactive_scene",
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
    assert [s["kind"] for s in body["sections"]] == ["practice", "interactive_scene"]

    # 覆盖写：再提交一份只留最后一个环节
    r = client.put(
        url,
        headers=auth_headers(teacher["token"]),
        json={"sections": [payload["sections"][1]]},
    )
    assert r.status_code == 200, r.text
    assert r.json()["section_count"] == 1
    assert r.json()["sections"][0]["id"] == "b"

    # 未知 kind：422，且**原内容不动**
    bad = client.put(
        url,
        headers=auth_headers(teacher["token"]),
        json={"sections": [{"kind": "video_clip", "title": "视频"}]},
    )
    assert bad.status_code == 422, bad.text
    assert bad.json()["code"] == ErrCode.COURSEWARE_BAD_KIND.value
    after = client.get(
        f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
    ).json()
    assert after["section_count"] == 1


def test_clearing_sections_writes_sql_null(client, teacher, drafted):
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


def test_courseware_survives_knowledge_point_deletion(client, teacher, drafted):
    """知识点被 ADR-0064 清理后课件**存活**，``kp_missing=True``（§4.1）。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    _delete_kp(teacher["kp"])

    got = client.get(
        f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
    )
    assert got.status_code == 200, got.text
    body = got.json()
    assert body["kp_missing"] is True
    # 展示靠快照：名字还在，环节还在
    assert body["kp_name"] == KP_NAME
    assert body["section_count"] == 3

    listed = client.get(
        "/api/v1/courseware", headers=auth_headers(teacher["token"])
    ).json()
    assert [r["kp_missing"] for r in listed] == [True]


def test_status_never_blocks_reads(client, teacher, drafted):
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
                json={"sections": [{"kind": "practice", "title": "练", "script": "?"}]},
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


def test_recent_follows_latest_update(client, teacher, drafted):
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


def test_delete_courseware(client, teacher, drafted):
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


def test_draft_failure_is_not_reported_as_missing_model(client, teacher, monkeypatch):
    """起草失败要给**人话原因**，不许被抹成「请添加模型」（ADR-0038）。"""

    def _boom(**_kwargs):
        raise AppErrorException(ErrCode.LLM_REQUEST_FAILED, "AI 起草课件失败：模型返回超时")

    monkeypatch.setattr(service, "draft_sections", _boom)
    r = _create(client, teacher["token"], teacher["kp"])
    assert r.status_code == 502, r.text
    body = r.json()
    assert body["code"] == ErrCode.LLM_REQUEST_FAILED.value
    assert "超时" in body["message"]
    assert "未配置模型" not in body["message"]
