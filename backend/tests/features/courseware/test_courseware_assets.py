"""课件素材端点单测（ADR-0067 §3.5 切片 2）：上传 / 列表 / 删除 / 取原图 + 归属隔离。

覆盖的每条都是本切片的显式决策，不是实现细节：

- 落盘走资料库现成的 per-teacher 目录（不新造根目录）；
- 只收 ``COURSEWARE_ASSET_MIMES``（非图片 422），不限制单文件大小；
- 越权行对别人表现为 404（不存在与越权同一错误，不泄露存在性）；
- **被课件引用也允许删**（决策 10 / §4.2）。
"""

import io
from pathlib import Path

import pytest
from sqlmodel import Session, delete, select

from app.core.db import engine
from app.db.models import Courseware, CoursewareAsset, KnowledgePoint, User
from tests.utils.user import auth_headers, login, register_teacher

# 1×1 透明 PNG：既是合法图片（可供宽高探测），又小到不会被上限拦下
_PNG_1X1 = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06"
    b"\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00"
    b"\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
)


@pytest.fixture()
def teacher_a(client) -> str:
    register_teacher(client, username="cw_asset_a", password="pw123456")
    return login(client, "cw_asset_a", "pw123456").json()["access_token"]


@pytest.fixture()
def teacher_b(client) -> str:
    register_teacher(client, username="cw_asset_b", password="pw123456")
    return login(client, "cw_asset_b", "pw123456").json()["access_token"]


@pytest.fixture(autouse=True)
def _isolated_courseware_rows():
    """每个用例前后清空课件两表：素材行跨用例累积会让「只含本人素材」失真。

    只清课件线自己的表——用户 / 资料等由全局 conftest 在套件结束时回收。
    """
    _wipe()
    yield
    _wipe()


def _wipe() -> None:
    with Session(engine) as session:
        session.execute(delete(CoursewareAsset))
        session.execute(delete(Courseware))
        session.commit()


@pytest.fixture()
def upload_root(client, monkeypatch, tmp_path: Path) -> Path:
    """落盘指到临时目录：不污染 backend/data/materials。"""
    root = tmp_path / "materials"
    monkeypatch.setattr(
        "app.features.courseware.asset_service.settings.MATERIAL_UPLOAD_ROOT", str(root)
    )
    return root


def _upload(client, token, *, filename="蝴蝶.png", content=_PNG_1X1, mime="image/png"):
    return client.post(
        "/api/v1/courseware/assets",
        headers=auth_headers(token),
        files={"file": (filename, io.BytesIO(content), mime)},
    )


def _list(client, token) -> list[dict]:
    return client.get("/api/v1/courseware/assets", headers=auth_headers(token)).json()


def _user_id(session: Session, username: str):
    return session.exec(select(User).where(User.username == username)).one().id


# ── 上传 ─────────────────────────────────────────────────────────────────


def test_upload_asset_stores_file_and_returns_url(client, teacher_a, upload_root):
    r = _upload(client, teacher_a)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["name"] == "蝴蝶.png"
    assert body["mime"] == "image/png"
    assert body["size_bytes"] == len(_PNG_1X1)
    # url 由后端拼好下发（前端不自己拼鉴权前缀）
    assert body["url"] == f"/api/v1/courseware/assets/{body['id']}/file"

    # 落盘在 per-teacher 目录下，且字节原样保留
    stored = [p for p in upload_root.rglob("*") if p.is_file()]
    assert len(stored) == 1, [str(p) for p in stored]
    assert stored[0].read_bytes() == _PNG_1X1
    assert stored[0].parent != upload_root  # {teacher_id}/ 子目录，不是直接落根上


def test_upload_reads_image_size(client, teacher_a, upload_root):
    """宽高只是可选优化（布局按可用宽度自适应）：读到就带，读不到留空。"""
    pytest.importorskip("PIL")  # pillow 在依赖锁里（经 genkit 传入）；缺失时降级为 None
    body = _upload(client, teacher_a).json()
    assert (body["width"], body["height"]) == (1, 1)


def test_non_image_mime_rejected(client, teacher_a, upload_root):
    r = _upload(client, teacher_a, filename="教材.pdf", mime="application/pdf")
    assert r.status_code == 422
    assert r.json()["code"] == "CW_91005"
    # 拒绝的上传不留残留文件
    assert [p for p in upload_root.rglob("*") if p.is_file()] == []


# ── 列表与归属隔离 ───────────────────────────────────────────────────────


def test_list_assets_only_own(client, teacher_a, teacher_b, upload_root):
    asset_a = _upload(client, teacher_a).json()
    asset_b = _upload(client, teacher_b, filename="剪纸.png").json()

    assert [a["id"] for a in _list(client, teacher_a)] == [asset_a["id"]]
    assert [a["id"] for a in _list(client, teacher_b)] == [asset_b["id"]]


def test_other_teacher_asset_is_404(client, teacher_a, teacher_b, upload_root):
    asset_id = _upload(client, teacher_a).json()["id"]

    # 取原图 / 删除：越权与不存在同一语义（404，不泄露存在性）
    r = client.get(
        f"/api/v1/courseware/assets/{asset_id}/file", headers=auth_headers(teacher_b)
    )
    assert r.status_code == 404
    assert r.json()["code"] == "CW_91003"

    r = client.delete(
        f"/api/v1/courseware/assets/{asset_id}", headers=auth_headers(teacher_b)
    )
    assert r.status_code == 404
    assert r.json()["code"] == "CW_91003"

    # 越权尝试没有副作用：本人的素材还在
    assert [a["id"] for a in _list(client, teacher_a)] == [asset_id]


# ── 删除（决策 10）───────────────────────────────────────────────────────


def test_delete_asset_referenced_by_courseware_succeeds(
    client, teacher_a, upload_root
):
    """被课件引用**也允许删**（ADR-0067 §4.2 / 决策 10）：不查引用计数、不级联课件。"""
    asset_id = _upload(client, teacher_a).json()["id"]

    with Session(engine) as session:
        courseware = Courseware(
            teacher_id=_user_id(session, "cw_asset_a"),
            subject="数学",
            grade=3,
            semester="上学期",
            kp_name="图形的运动（轴对称）",
            title="轴对称",
            sections=[
                {
                    "id": "s1",
                    "kind": "media_gallery",
                    "title": "生活中的轴对称",
                    "script": "这些图形有什么共同点？",
                    "payload": {"items": [{"asset_id": asset_id, "caption": "蝴蝶"}]},
                }
            ],
        )
        session.add(courseware)
        session.commit()
        courseware_id = courseware.id

    r = client.delete(
        f"/api/v1/courseware/assets/{asset_id}", headers=auth_headers(teacher_a)
    )
    assert r.status_code == 200, r.text
    assert r.json() == {"deleted": True}

    # 素材行与物理文件都清掉
    assert _list(client, teacher_a) == []
    assert [p for p in upload_root.rglob("*") if p.is_file()] == []

    # 引用它的课件**存活**（占位由展示侧渲染，不做级联）
    with Session(engine) as session:
        assert session.get(Courseware, courseware_id) is not None


# ── 取原图 ───────────────────────────────────────────────────────────────


def test_file_endpoint_returns_original_bytes(client, teacher_a, upload_root):
    body = _upload(client, teacher_a).json()

    r = client.get(body["url"], headers=auth_headers(teacher_a))
    assert r.status_code == 200, r.text
    assert r.content == _PNG_1X1
    assert r.headers["content-type"].startswith("image/png")


def test_file_endpoint_404_when_asset_missing(client, teacher_a, upload_root):
    r = client.get(
        "/api/v1/courseware/assets/4b2f0c2e-0000-4000-8000-000000000000/file",
        headers=auth_headers(teacher_a),
    )
    assert r.status_code == 404
    assert r.json()["code"] == "CW_91003"


# ── T04 素材库检索（按知识点 / 文件名过滤 + 跨教师 403）────────────────────────


def _make_kp(session: Session, teacher_id, name: str) -> KnowledgePoint:
    kp = KnowledgePoint(
        teacher_id=teacher_id, subject="数学", grade=3, semester="上学期", name=name
    )
    session.add(kp)
    session.commit()
    session.refresh(kp)
    return kp


def _insert_asset(session: Session, teacher_id, name: str, kp_id=None) -> CoursewareAsset:
    asset = CoursewareAsset(
        teacher_id=teacher_id,
        name=name,
        storage_key=f"{teacher_id}/{name}",
        mime="image/png",
        size_bytes=1,
        knowledge_point_id=kp_id,
    )
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset


def _search(client, token, *, kp=None, filename=None) -> "object":
    params: dict = {}
    if kp is not None:
        params["knowledge_point"] = str(kp)
    if filename is not None:
        params["filename"] = filename
    return client.get(
        "/api/v1/courseware/assets", headers=auth_headers(token), params=params
    )


def test_search_returns_teacher_scoped_assets(client, teacher_a, teacher_b, upload_root):
    """素材库只返回本人素材，跨教师不泄漏。"""
    with Session(engine) as session:
        _insert_asset(session, _user_id(session, "cw_asset_a"), "蝴蝶.png")
        _insert_asset(session, _user_id(session, "cw_asset_b"), "剪纸.png")
    r = _search(client, teacher_a)
    assert r.status_code == 200
    assert [a["name"] for a in r.json()] == ["蝴蝶.png"]


def test_search_filters_by_knowledge_point(client, teacher_a, upload_root):
    """按知识点过滤只回该知识点素材；响应带回 knowledge_point_id；不传则全量。"""
    with Session(engine) as session:
        kp = _make_kp(session, _user_id(session, "cw_asset_a"), name="轴对称")
        kp_id = kp.id
        _insert_asset(
            session, _user_id(session, "cw_asset_a"), "蝴蝶.png", kp_id=kp_id
        )
        _insert_asset(session, _user_id(session, "cw_asset_a"), "通用图.png")
    r = _search(client, teacher_a, kp=kp_id)
    assert r.status_code == 200
    body = r.json()
    assert [a["name"] for a in body] == ["蝴蝶.png"]
    assert body[0]["knowledge_point_id"] == str(kp_id)

    # 不传过滤 → 本人全部（含未绑知识点的通用素材）
    r = _search(client, teacher_a)
    assert {a["name"] for a in r.json()} == {"蝴蝶.png", "通用图.png"}


def test_search_filters_by_filename(client, teacher_a, upload_root):
    """文件名子串过滤（大小写不敏感，SQLite LIKE 对 ASCII 不敏感）。"""
    with Session(engine) as session:
        _insert_asset(session, _user_id(session, "cw_asset_a"), "蝴蝶.png")
        _insert_asset(session, _user_id(session, "cw_asset_a"), "剪纸.png")
    r = _search(client, teacher_a, filename="蝶")
    assert r.status_code == 200
    assert [a["name"] for a in r.json()] == ["蝴蝶.png"]


def test_search_cross_teacher_kp_is_403(client, teacher_a, teacher_b, upload_root):
    """拿别人的知识点来过滤 → 403（越权，不降级成 404 伪装不存在）。"""
    with Session(engine) as session:
        kp = _make_kp(session, _user_id(session, "cw_asset_b"), name="他人知识点")
        kp_id = kp.id
    r = _search(client, teacher_a, kp=kp_id)
    assert r.status_code == 403
    assert r.json()["code"] == "SYS_10002"
