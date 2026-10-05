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

    def test_move_material_to_folder_and_back(self, client, ptoken, upload_root):
        folder = _create_folder(client, ptoken, subject="语文", grade=2)
        r = _upload(
            client,
            ptoken,
            filename="生词.txt",
            content="比喻、拟人。".encode(),
            folder_id=folder["id"],
        )
        mat_id = r.json()["material"]["id"]
        # 移回根目录（folder_id=null）
        r = client.patch(
            f"/api/v1/materials/{mat_id}",
            headers=auth_headers(ptoken),
            json={"folder_id": None},
        )
        assert r.status_code == 200, r.text
        assert r.json()["folder_id"] is None
        # 移到另一个目录
        other = _create_folder(client, ptoken, name="其它")
        r = client.patch(
            f"/api/v1/materials/{mat_id}",
            headers=auth_headers(ptoken),
            json={"folder_id": other["id"]},
        )
        assert r.status_code == 200 and r.json()["folder_id"] == other["id"]
        # 列表按目录过滤：only this material in `other`
        r = client.get(
            f"/api/v1/materials?folder_id={other['id']}",
            headers=auth_headers(ptoken),
        )
        assert r.status_code == 200 and len(r.json()) == 1
        # 越权目录被拒（403，不降级成 404）
        register_parent(client, username="mat_move_other", password="pw123456")
        other_p = login(client, "mat_move_other", "pw123456").json()["access_token"]
        r = client.patch(
            f"/api/v1/materials/{mat_id}",
            headers=auth_headers(other_p),
            json={"folder_id": folder["id"]},
        )
        assert r.status_code == 403


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

    def test_notice_explains_skeleton_only_scope(self, client, ptoken, upload_root):
        """只有骨架兜底时必须**明说**（ADR-0061 §L）。

        回归背景：骨架是分不出学期的大颗粒目录，家长在某范围切学期时下拉逐字相同，
        不解释就像「联动坏了」。这里钉住 notice 的出现条件。
        """
        # 空账号 + 未确认任何知识点 → 上/下学期都只剩骨架
        for semester in ("上学期", "下学期"):
            r = client.get(
                f"/api/v1/materials/knowledge-points?subject=数学&grade=5&semester={semester}",
                headers=auth_headers(ptoken),
            )
            assert r.status_code == 200
            body = r.json()
            assert all(i["id"] is None for i in body["items"]), "前置：应只有骨架"
            assert body["notice"], f"只有骨架的 {semester} 范围必须给出说明"
            assert "不分学期" in body["notice"]

        # 不限学期（''）=并集语义，不属于「某学期没有」的场景 → 不出notice
        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=5",
            headers=auth_headers(ptoken),
        )
        assert r.json()["notice"] == ""

        # 该学期有真实知识点后 → notice 消失
        client.post(
            "/api/v1/materials/knowledge-points/confirm",
            headers=auth_headers(ptoken),
            json={
                "names": ["真实点"],
                "subject": "数学",
                "grade": 5,
                "semester": "上学期",
            },
        )
        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=5&semester=上学期",
            headers=auth_headers(ptoken),
        )
        assert r.json()["notice"] == "", "有真实知识点后不该再提示骨架兜底"

    def test_semester_scope_union_vs_exact(self, client, ptoken, upload_root):
        """学期维度（ADR-0061）：不限学期 = 并集；限定学期 = 精确匹配。

        回归背景：早期实现对 ``semester=''`` 也做精确匹配，而资料涌现的知识点几乎
        都带「上/下学期」——于是布置任务表单默认态（不限学期）永远只拿到骨架兜底，
        家长看到的就是「知识点不随学期切换」。这里钉住两态语义。
        """
        # 确认三个同学科同学年级、不同学期的知识点落库。
        for semester, name in (
            ("上学期", "上册专属点"),
            ("下学期", "下册专属点"),
        ):
            r = client.post(
                "/api/v1/materials/knowledge-points/confirm",
                headers=auth_headers(ptoken),
                json={
                    "names": [name],
                    "subject": "数学",
                    "grade": 4,
                    "semester": semester,
                },
            )
            assert r.status_code == 200, r.text

        def _names(semester: str | None) -> list[str]:
            url = "/api/v1/materials/knowledge-points?subject=数学&grade=4"
            if semester is not None:
                url += f"&semester={semester}"
            r = client.get(url, headers=auth_headers(ptoken))
            assert r.status_code == 200, r.text
            return [i["name"] for i in r.json()["items"] if i["id"] is not None]

        # 精确学期：只含该学期，且响应带semester 供前端标注。
        assert _names("上学期") == ["上册专属点"]
        assert _names("下学期") == ["下册专属点"]
        # 不限学期（连字符都不传，等价 ''）：并集两个学期。
        assert set(_names(None)) == {"上册专属点", "下册专属点"}
        assert set(_names("")) == {"上册专属点", "下册专属点"}

        # 响应带semester 字段（前端据此给跨学期并集加后缀标注）。
        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=4",
            headers=auth_headers(ptoken),
        )
        by_name = {i["name"]: i.get("semester") for i in r.json()["items"]}
        assert by_name["上册专属点"] == "上学期"
        assert by_name["下册专属点"] == "下学期"


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


# ── B4：VectorKnowledgeRetriever（dense + 词法 + RRF）───────────────────


class TestVectorRetrieval:
    def test_hybrid_retrieval_and_filter(self, client, ptoken, upload_root, db, monkeypatch):
        """向量化后经 build_retriever('vector') 检索：dense+词法融合，快照带资料名。"""
        folder = _create_folder(client, ptoken, name="数学三上", subject="数学", grade=3)

        async def kw_embed(texts):
            # 关键词向量：含「鸡兔」→ [1,0,0,0]，否则 [0,1,0,0]
            return [[1.0, 0.0, 0.0, 0.0] if "鸡兔" in t else [0.0, 1.0, 0.0, 0.0] for t in texts]

        monkeypatch.setattr(
            "app.features.materials.indexing.settings.EMBEDDING_PROVIDER", "ollama"
        )
        monkeypatch.setattr("app.features.materials.indexing.embed_texts", kw_embed)
        mat_ids = []
        for name, content in (
            ("鸡兔同笼.txt", "鸡兔同笼问题：设鸡有 x 只，兔有 y 只，则 x+y=头数，2x+4y=脚数。"),
            ("运算律.txt", "乘法分配律：a×(b+c)=a×b+a×c，这是简便运算的重要依据。"),
        ):
            r = _upload(client, ptoken, filename=name, content=content.encode(), folder_id=folder["id"])
            mat_ids.append(r.json()["material"]["id"])
        for mid in mat_ids:
            r = client.post(f"/api/v1/materials/{mid}/vectorize", headers=auth_headers(ptoken))
            assert r.json()["index_state"] == "ready", r.text

        # 切到 vector 检索：查询向量指向「鸡兔」簇
        monkeypatch.setattr("app.core.config.settings.RETRIEVER_PROVIDER", "vector")

        async def q_embed(texts):
            return [[1.0, 0.0, 0.0, 0.0] for _ in texts]

        monkeypatch.setattr("app.features.materials.retrieval.embed_texts", q_embed)

        from sqlmodel import select

        from app.db.models import User
        from app.domain.retriever import build_retriever

        parent = db.exec(select(User).where(User.username == "mat_parent")).one()
        retriever = build_retriever(session=db, parent_id=parent.id)
        chunks = retriever.retrieve(subject="数学", grade=3, knowledge_point="鸡兔同笼", query="鸡兔同笼")
        assert chunks, "向量+词法双路不应为空"
        assert all(c.source == "vector" for c in chunks)
        # RRF 融合后首命中是 dense+词法双高分的「鸡兔」片段，快照带资料名
        assert chunks[0].source_name == "鸡兔同笼.txt"
        assert "鸡兔同笼" in chunks[0].content

    def test_version_mismatch_excluded(self, client, ptoken, upload_root, db, monkeypatch):
        """版本戳双保险：embed_model 与当前配置不符的 chunk 不参与检索（stale 语义）。"""
        from sqlmodel import select

        from app.db.models import MaterialChunk, User
        from app.features.materials import repository as repo
        from app.features.materials.retrieval import VectorKnowledgeRetriever

        parent = db.exec(select(User).where(User.username == "mat_parent")).one()
        mats = repo.list_materials(db, parent_id=parent.id, folder_id=None)
        assert mats, "前置：已有已上传资料"
        old = mats[0]
        db.add(
            MaterialChunk(
                parent_id=parent.id,
                material_id=old.id,
                seq=0,
                content="旧模型的孤儿片段不该被召回",
                embed_model="旧模型",
                chunker_ver="v0",
                subject=old.subject or "数学",
                grade=old.grade or 3,
            )
        )
        db.commit()
        retriever = VectorKnowledgeRetriever(db, parent.id)
        chunks = retriever.retrieve(
            subject=old.subject or "数学",
            grade=old.grade or 3,
            knowledge_point="任意",
            query="孤儿片段",
        )
        assert all("旧模型的孤儿片段" not in c.content for c in chunks)
