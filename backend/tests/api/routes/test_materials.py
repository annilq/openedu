"""资料库 API 单测（ADR-0055 B2）：上传解析 / 目录继承 / 知识点选择器 / 权限。

测试不接真实模型：未配置 ModelConfig 时提取应落 skipped_no_engine，
资料本体照常入库（提取失败不阻塞入库是 ADR-0055 的显式语义）。
"""

import io
from pathlib import Path

import pytest

from app.features.materials.embedder import EmbeddingUnavailableError
from tests.utils.user import auth_headers, login, register_parent


@pytest.fixture()
def ptoken(client):
    register_parent(client, username="mat_parent", password="pw123456")
    r = login(client, "mat_parent", "pw123456")
    return r.json()["access_token"]


@pytest.fixture()
def upload_root(client, monkeypatch, tmp_path: Path) -> Path:
    """上传落盘指到临时目录：不污染 backend/data。"""
    root = tmp_path / "materials"
    monkeypatch.setattr(
        "app.features.materials.service.settings.MATERIAL_UPLOAD_ROOT", str(root)
    )
    return root


def _create_folder(client, token, **kw) -> dict:
    r = client.post(
        "/api/v1/materials/folders",
        headers=auth_headers(token),
        json={
            "name": kw.get("name", "三年级数学"),
            "subject": kw.get("subject"),
            "grade": kw.get("grade"),
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


def _upload(client, token, *, filename, content: bytes, folder_id=None, **form):
    data = {"file": (filename, io.BytesIO(content))}
    fields = {"folder_id": folder_id} if folder_id else {}
    fields.update(form)
    return client.post(
        "/api/v1/materials/upload", headers=auth_headers(token), files=data, data=fields
    )


class TestUploadAndParse:
    def test_txt_upload_inherits_folder_meta(self, client, ptoken, upload_root):
        folder = _create_folder(
            client, ptoken, name="三年级数学", subject="数学", grade=3
        )
        r = _upload(
            client,
            ptoken,
            filename="口算练习.txt",
            content="两位数乘法练习：12×3=？ 整十数乘两位数。".encode(),
            folder_id=folder["id"],
        )
        assert r.status_code == 200, r.text
        body = r.json()
        # 未配置模型：提取跳过但资料入库（ADR-0055：提取失败不阻塞）
        assert body["extraction"] == "skipped_no_engine"
        mat = body["material"]
        assert mat["text_length"] > 0
        assert mat["index_state"] == "pending"
        # 目录元数据继承（ADR-0055 §2）
        assert mat["subject"] == "数学"
        assert mat["grade"] == 3
        # 落盘真实存在（storage_key 是内部实现，不暴露给响应）
        files = list(upload_root.rglob("*"))
        assert any(f.is_file() and f.suffix == ".txt" for f in files)

    def test_unsupported_extension_422(self, client, ptoken, upload_root):
        r = _upload(client, ptoken, filename="照片.jpg", content=b"\xff\xd8\xe0")
        assert r.status_code == 422
        assert r.json()["code"] == "MAT_90001"

    def test_oversize_413(self, client, ptoken, upload_root, monkeypatch):
        monkeypatch.setattr(
            "app.features.materials.service.settings.MATERIAL_MAX_BYTES", 100
        )
        r = _upload(client, ptoken, filename="big.txt", content=b"x" * 101)
        assert r.status_code == 413

    def test_empty_text_422(self, client, ptoken, upload_root):
        r = _upload(client, ptoken, filename="blank.txt", content=b"   \n  ")
        assert r.status_code == 422

    def test_requires_parent(self, client, ptoken, upload_root):
        # 娃娃账号无资料库
        r = client.post(
            "/api/v1/children",
            headers=auth_headers(ptoken),
            json={
                "username": "mat_kid",
                "password": "kid123456",
                "display_name": "娃",
                "grade": 3,
                "role": "child",
            },
        )
        assert r.status_code == 201, r.text
        kid = login(client, "mat_kid", "kid123456").json()["access_token"]
        r = client.get("/api/v1/materials", headers=auth_headers(kid))
        assert r.status_code == 403


class TestFolders:
    def test_folder_crud_and_not_empty_guard(self, client, ptoken, upload_root):
        folder = _create_folder(client, ptoken, subject="数学", grade=3)
        _upload(
            client,
            ptoken,
            filename="a.txt",
            content="加减法".encode(),
            folder_id=folder["id"],
        )
        # 有资料：拒删（409）
        r = client.delete(
            f"/api/v1/materials/folders/{folder['id']}", headers=auth_headers(ptoken)
        )
        assert r.status_code == 409
        # 子目录环检测：把目录挂到自己子目录下被拒
        sub = _create_folder(client, ptoken, name="子目录")
        r = client.patch(
            f"/api/v1/materials/folders/{sub['id']}",
            headers=auth_headers(ptoken),
            json={"parent_folder_id": str(folder["id"])},
        )
        assert r.status_code == 200
        r = client.patch(
            f"/api/v1/materials/folders/{folder['id']}",
            headers=auth_headers(ptoken),
            json={"parent_folder_id": sub["id"]},
        )
        assert r.status_code == 422

    def test_cross_parent_invisible(self, client, ptoken, upload_root):
        folder = _create_folder(client, ptoken)
        register_parent(client, username="mat_other", password="pw123456")
        other = login(client, "mat_other", "pw123456").json()["access_token"]
        r = client.get(
            f"/api/v1/materials?folder_id={folder['id']}", headers=auth_headers(other)
        )
        assert r.status_code == 403


class TestMaterialLifecycle:
    def test_list_get_delete(self, client, ptoken, upload_root):
        folder = _create_folder(client, ptoken, subject="语文", grade=2)
        r = _upload(
            client,
            ptoken,
            filename="生词.txt",
            content="比喻、拟人。".encode(),
            folder_id=folder["id"],
        )
        mat_id = r.json()["material"]["id"]
        # 列表
        r = client.get(
            f"/api/v1/materials?folder_id={folder['id']}", headers=auth_headers(ptoken)
        )
        assert r.status_code == 200 and len(r.json()) == 1
        # 详情
        r = client.get(f"/api/v1/materials/{mat_id}", headers=auth_headers(ptoken))
        assert r.status_code == 200 and r.json()["name"] == "生词.txt"
        # 删除
        r = client.delete(f"/api/v1/materials/{mat_id}", headers=auth_headers(ptoken))
        assert r.status_code == 200 and r.json()["deleted"] is True
        # 删除后不可再取（guard 纪律：不存在与越权同为 403，不降级成 404）
        assert (
            client.get(
                f"/api/v1/materials/{mat_id}", headers=auth_headers(ptoken)
            ).status_code
            == 403
        )


class TestKnowledgePoints:
    def test_skeleton_fallback_and_confirm(self, client, ptoken, upload_root):
        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=3",
            headers=auth_headers(ptoken),
        )
        assert r.status_code == 200
        items = r.json()["items"]
        assert items, "骨架兜底不应为空（ADR-0055 §4 冷启动）"
        assert all(
            i["source"] == "skeleton" and i["status"] == "curated" for i in items
        )
        # 确认骨架条目 → 落库转正
        r = client.post(
            "/api/v1/materials/knowledge-points/confirm",
            headers=auth_headers(ptoken),
            json={"names": [items[0]["name"]], "subject": "数学", "grade": 3},
        )
        assert r.status_code == 200 and r.json()["confirmed"] == 1
        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=3",
            headers=auth_headers(ptoken),
        )
        db_rows = [i for i in r.json()["items"] if i["id"] is not None]
        assert len(db_rows) == 1 and db_rows[0]["name"] == items[0]["name"]
        # 不重复：确认后列表长度不变（DB 行顶掉骨架位）
        r2 = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=3",
            headers=auth_headers(ptoken),
        )
        assert len(r2.json()["items"]) == len(items)


# ── B3：向量化状态机 ────────────────────────────────────────────────────


async def _fake_embed(texts):
    """确定性假向量：4 维，由文本哈希决定（同文同向量，异文异向量）。"""
    out = []
    for t in texts:
        h = abs(hash(t)) % 1000
        out.append([h % 7 / 7, h % 5 / 5, h % 3 / 3, 1.0])
    return out


@pytest.fixture()
def uploaded_mat_id(client, ptoken, upload_root):
    folder = _create_folder(client, ptoken, name="数学三上", subject="数学", grade=3)
    r = _upload(
        client,
        ptoken,
        filename="乘法.txt",
        content=("两位数乘法。先算个位，再算十位，满十进一。" * 30).encode(),
        folder_id=folder["id"],
    )
    assert r.status_code == 200, r.text
    return r.json()["material"]["id"]


class TestVectorization:
    def test_vectorize_requires_config(self, client, ptoken, uploaded_mat_id):
        # EMBEDDING_PROVIDER 默认 none：显式 500 + LLM_UNAVAILABLE，不假装成功
        r = client.post(
            f"/api/v1/materials/{uploaded_mat_id}/vectorize",
            headers=auth_headers(ptoken),
        )
        assert r.status_code == 500
        assert r.json()["code"] == "SYS_10006"

    def test_vectorize_success_and_rebuild(
        self, client, ptoken, uploaded_mat_id, monkeypatch
    ):
        monkeypatch.setattr(
            "app.features.materials.indexing.settings.EMBEDDING_PROVIDER", "ollama"
        )
        monkeypatch.setattr("app.features.materials.indexing.embed_texts", _fake_embed)
        r = client.post(
            f"/api/v1/materials/{uploaded_mat_id}/vectorize",
            headers=auth_headers(ptoken),
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["index_state"] == "ready"
        assert body["embed_model"] == "bge-m3"
        assert body["index_error"] is None

        # 重新向量化：不产生重复片段（全量重建语义）
        r2 = client.post(
            f"/api/v1/materials/{uploaded_mat_id}/vectorize",
            headers=auth_headers(ptoken),
        )
        assert r2.status_code == 200
        assert r2.json()["index_state"] == "ready"

    def test_vectorize_failure_marks_failed(
        self, client, ptoken, uploaded_mat_id, monkeypatch
    ):
        monkeypatch.setattr(
            "app.features.materials.indexing.settings.EMBEDDING_PROVIDER", "ollama"
        )

        def _boom(texts):
            raise EmbeddingUnavailableError("embedding 服务调用失败：连接拒绝")

        monkeypatch.setattr("app.features.materials.indexing.embed_texts", _boom)
        r = client.post(
            f"/api/v1/materials/{uploaded_mat_id}/vectorize",
            headers=auth_headers(ptoken),
        )
        assert r.status_code == 200, r.text  # 失败落态不抛 500
        body = r.json()
        assert body["index_state"] == "failed"
        assert "连接拒绝" in body["index_error"]

    def test_stale_marked_on_model_change(
        self, client, ptoken, uploaded_mat_id, monkeypatch
    ):
        monkeypatch.setattr(
            "app.features.materials.indexing.settings.EMBEDDING_PROVIDER", "ollama"
        )
        monkeypatch.setattr("app.features.materials.indexing.embed_texts", _fake_embed)
        assert (
            client.post(
                f"/api/v1/materials/{uploaded_mat_id}/vectorize",
                headers=auth_headers(ptoken),
            ).json()["index_state"]
            == "ready"
        )
        # 换模型 → 列表惰性标记 stale（ADR-0055 §5 向量绑定模型）
        monkeypatch.setattr(
            "app.features.materials.indexing.settings.EMBEDDING_MODEL",
            "qwen3-embedding",
        )
        r = client.get("/api/v1/materials", headers=auth_headers(ptoken))
        states = {m["id"]: m["index_state"] for m in r.json()}
        assert states[uploaded_mat_id] == "stale"
