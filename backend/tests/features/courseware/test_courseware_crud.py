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
    """起草替身：确定性三环节（去 kind·expand 后不再带 kind，统一内容块容器）。

    交互演示环节用 payload 里的 SceneSpec kind（ADR-0061 渲染器名 reflection）标识，
    与已删除的环节 kind 字段是两件事——场景测试据此定位「交互演示」段。
    """
    return [
        service.CoursewareSection(
            title="生活中的对称",
            script="这些图形有什么共同点？",
            payload={"items": [], "prompt": "先找出共同点"},
        ),
        service.CoursewareSection(
            title="判断是否轴对称",
            script="沿这条线对折，两边能重合吗？",
            payload={"kind": "reflection", "title": "轴对称"},
        ),
        service.CoursewareSection(
            title="课堂练习",
            script="下面哪些图形是轴对称图形？",
            payload={"qtype": "choice", "count": 3},
        ),
    ]


def _interactive(body: dict) -> dict:
    """定位「交互演示」环节：去 kind 后靠 payload 里的 SceneSpec kind 兜底识别。"""
    return next(
        s for s in body["sections"]
        if (s.get("payload") or {}).get("kind") == "reflection"
    )


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
    # 去 kind·expand：起草产物不再带 kind（统一内容块），下发为 None。
    assert all(s["kind"] is None for s in body["sections"])
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
    """``PUT /sections`` 整体覆盖写；去 kind 后未知 kind 不再 422（kind 退化为可选只读）。"""
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

    # 去 kind·expand：未知 kind 不再 422（kind 退化为可选只读兼容字段），PUT 成功且
    # 原内容不动（kind 存为给定值，演示页按内容渲染不依赖它）。
    bad = client.put(
        url,
        headers=auth_headers(teacher["token"]),
        json={"sections": [{"kind": "video_clip", "title": "视频"}]},
    )
    assert bad.status_code == 200, bad.text
    after = client.get(
        f"/api/v1/courseware/{cw['id']}", headers=auth_headers(teacher["token"])
    ).json()
    assert after["section_count"] == 1
    assert after["sections"][0]["kind"] == "video_clip"


def test_replace_sections_roundtrips_script_segments(client, teacher, drafted):
    """PUT /sections 透传话术多段 + 重点（T02），GET 原样回；旧单串 script 仍兼容。"""
    cw = _create(client, teacher["token"], teacher["kp"]).json()
    url = f"/api/v1/courseware/{cw['id']}/sections"
    payload = {
        "sections": [
            {
                "id": "a",
                "kind": "media_gallery",
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


def _current_draft_shape():
    """与 ``_draft()`` 完全一致的当前稿（用于「全 unchanged」对照）。"""
    return [
        {
            "kind": "media_gallery",
            "title": "生活中的对称",
            "script": "这些图形有什么共同点？",
            "payload": {"items": [], "prompt": "先找出共同点"},
        },
        {
            "kind": "interactive_scene",
            "title": "判断是否轴对称",
            "script": "沿这条线对折，两边能重合吗？",
            "payload": {"kind": "reflection", "title": "轴对称"},
        },
        {
            "kind": "practice",
            "title": "课堂练习",
            "script": "下面哪些图形是轴对称图形？",
            "payload": {"qtype": "choice", "count": 3},
        },
    ]


def test_redraft_diff_is_per_segment(client, teacher, drafted):
    """``POST /redraft`` 返回逐段 diff：当前稿改过一段→modified，草稿多出的→added，
    当前稿独有的→removed；且**不新建课件副本**（列表数不变）。"""
    r = _create(client, teacher["token"], teacher["kp"])
    assert r.status_code == 200, r.text
    cw_id = r.json()["id"]

    # 当前稿：把 A 的提问改了（modified），并加了一段草稿里没有的旧环节（removed）。
    current = [
        {
            "kind": "media_gallery",
            "title": "生活中的对称",
            "script": "改过的提问",  # 与草稿不同 → modified
            "payload": {},
        },
        {
            "kind": "practice",
            "title": "旧环节",  # 草稿里没有 → removed
            "script": "旧",
            "payload": {"qtype": "choice"},
        },
    ]
    r = client.put(
        f"/api/v1/courseware/{cw_id}/sections",
        headers=auth_headers(teacher["token"]),
        json={"sections": current},
    )
    assert r.status_code == 200, r.text

    # 重起草：draft_sections 仍返回确定性三环节 [A, B, C]。
    r = client.post(
        f"/api/v1/courseware/{cw_id}/redraft",
        headers=auth_headers(teacher["token"]),
    )
    assert r.status_code == 200, r.text
    diff = r.json()["diff"]

    # 期望顺序：按草稿序铺 A(modified) / B(added) / C(added)，末尾收 旧环节(removed)。
    assert [d["status"] for d in diff] == ["modified", "added", "added", "removed"]
    assert diff[0]["current"]["title"] == "生活中的对称"
    assert diff[0]["drafted"]["title"] == "生活中的对称"
    assert diff[1]["status"] == "added" and diff[1]["drafted"]["title"] == "判断是否轴对称"
    assert diff[2]["status"] == "added" and diff[2]["drafted"]["title"] == "课堂练习"
    assert diff[3]["status"] == "removed" and diff[3]["current"]["title"] == "旧环节"

    # 不新建副本：列表仍是 1 份。
    r = client.get(
        "/api/v1/courseware",
        headers=auth_headers(teacher["token"]),
        params={"knowledge_point_id": str(teacher["kp"])},
    )
    assert r.status_code == 200
    assert len(r.json()) == 1


def test_redraft_diff_unchanged_when_current_matches_draft(client, teacher, drafted):
    """当前稿与草稿逐字一致 → 全部 unchanged（教师无需逐段翻）。"""
    r = _create(client, teacher["token"], teacher["kp"])
    cw_id = r.json()["id"]

    r = client.put(
        f"/api/v1/courseware/{cw_id}/sections",
        headers=auth_headers(teacher["token"]),
        json={"sections": _current_draft_shape()},
    )
    assert r.status_code == 200, r.text

    r = client.post(
        f"/api/v1/courseware/{cw_id}/redraft",
        headers=auth_headers(teacher["token"]),
    )
    assert r.status_code == 200, r.text
    diff = r.json()["diff"]
    assert [d["status"] for d in diff] == ["unchanged", "unchanged", "unchanged"]
    assert all(d["current"] is not None and d["drafted"] is not None for d in diff)


def test_redraft_diff_respects_ownership(client, teacher, drafted):
    """别人的课件读不到：重起草越权返回 404（归属只经 core.guard）。"""
    r = _create(client, teacher["token"], teacher["kp"])
    cw_id = r.json()["id"]

    # 另一个教师
    username = f"other_{uuid.uuid4().hex[:8]}"
    register_teacher(client, username=username)
    other_token = login(client, username, "pw123456").json()["access_token"]

    r = client.post(
        f"/api/v1/courseware/{cw_id}/redraft",
        headers=auth_headers(other_token),
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


def test_create_does_not_attach_kp_scene_to_interactive_section(client, teacher, drafted):
    """知识点配了场景，但 AI 起草环节没显式带场景 → 不自动补（演示按配置显示）。

    演示页只渲染课件里**显式保存**的 ``scene``；建课件时不再把知识点默认场景
    塞进每个交互环节，避免「我没配场景却显示了」的错觉。
    """
    _set_kp_scenes(teacher["kp"], [_REFLECTION_SCENE])
    body = _create(client, teacher["token"], teacher["kp"]).json()
    scene_section = _interactive(body)
    assert scene_section["scene"] is None


def test_attach_leaves_other_kinds_alone(client, teacher, drafted):
    """非交互环节（素材画廊 / 练习）不带场景；场景只可能由 AI 在交互环节显式给。

    建课件不再自动补场景，所以除起草环节自身携带外，其余环节 ``scene`` 一定为 None。
    """
    _set_kp_scenes(teacher["kp"], [_REFLECTION_SCENE])
    body = _create(client, teacher["token"], teacher["kp"]).json()
    interactive = _interactive(body)
    others = [s for s in body["sections"] if s is not interactive]
    assert others, "起草应含非交互环节"
    assert all(s["scene"] is None for s in others)


def test_no_kp_scene_means_no_scene_not_a_fabricated_one(client, teacher, drafted):
    """知识点没配场景 → 环节就是没有场景，**不臆造**一份。"""
    body = _create(client, teacher["token"], teacher["kp"]).json()
    scene_section = _interactive(body)
    assert scene_section["scene"] is None


def test_drafted_payload_scene_is_not_overridden(client, teacher, drafted, monkeypatch):
    """AI 起草未在顶层给 ``scene`` 时，保持 ``None``，绝不臆造或回退补一份。

    演示页只渲染显式保存的 ``scene``；起草环节若 AI 没给场景，落库即 ``None``，
    教师需在编辑器里显式关联后才会在演示中出现。
    """
    _set_kp_scenes(teacher["kp"], [_REFLECTION_SCENE])
    monkeypatch.setattr(
        service,
        "draft_sections",
        lambda **_k: [
            service.CoursewareSection(
                kind="interactive_scene",
                title="判定",
                script="对折看看",
                # 完整 SceneSpec（含 inputs）→ 视为 AI 已给场景
                payload={"kind": "reflection", "inputs": [], "title": "本题的图"},
            )
        ],
    )
    body = _create(client, teacher["token"], teacher["kp"]).json()
    scene_section = _interactive(body)
    assert scene_section["scene"] is None
    assert scene_section["payload"]["title"] == "本题的图"


def test_teacher_can_clear_scene_without_it_being_refilled(client, teacher, drafted):
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
                    "kind": "interactive_scene",
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
