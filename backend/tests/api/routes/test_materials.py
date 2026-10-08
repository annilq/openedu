"""资料库 API 单测（ADR-0055 B2）：上传解析 / 目录继承 / 知识点选择器 / 权限。

测试不接真实模型：未配置 ModelConfig 时提取应落 skipped_no_engine，
资料本体照常入库（提取失败不阻塞入库是 ADR-0055 的显式语义）。
"""

import io
import uuid
from pathlib import Path

import pytest

from app.features.materials.embedder import EmbeddingUnavailableError
from tests.utils.user import auth_headers, login, register_teacher


@pytest.fixture()
def ptoken(client):
    register_teacher(client, username="mat_teacher", password="pw123456")
    r = login(client, "mat_teacher", "pw123456")
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

    def test_requires_teacher(self, client, ptoken, upload_root):
        # 学生账号无资料库
        r = client.post(
            "/api/v1/students",
            headers=auth_headers(ptoken),
            json={
                "username": "mat_kid",
                "password": "kid123456",
                "display_name": "娃",
                "grade": 3,
                "role": "student",
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
            json={"teacher_folder_id": str(folder["id"])},
        )
        assert r.status_code == 200
        r = client.patch(
            f"/api/v1/materials/folders/{folder['id']}",
            headers=auth_headers(ptoken),
            json={"teacher_folder_id": sub["id"]},
        )
        assert r.status_code == 422

    def test_cross_teacher_invisible(self, client, ptoken, upload_root):
        folder = _create_folder(client, ptoken)
        register_teacher(client, username="mat_other", password="pw123456")
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
        register_teacher(client, username="mat_move_other", password="pw123456")
        other_p = login(client, "mat_move_other", "pw123456").json()["access_token"]
        r = client.patch(
            f"/api/v1/materials/{mat_id}",
            headers=auth_headers(other_p),
            json={"folder_id": folder["id"]},
        )
        assert r.status_code == 403


@pytest.fixture()
def solo(client):
    """**独立账号** (token, teacher_id)——知识点用例断言「空」的前提。

    为什么不用文件顶那个共享的 ``ptoken``：全量跑时它的名下已经堆了别的文件里上传
    的资料与知识点，「这个范围应该没有知识点」这类断言会随机失败。知识点用例大多
    在钉「某个范围里没有东西」，账号必须是干净的。

    teacher_id 按 username 精确取（不能用 ``select(User).first()``）：全量顺序下
    first() 拿到的是别人，写进去的知识点会落到另一家名下、查询侧永远看不到——
    这正是历史上「本地单跑绿、全量红」的成因。
    """
    from sqlmodel import Session as DBSession
    from sqlmodel import select

    from app.core.db import engine
    from app.db.models import User

    username = f"kp_{uuid.uuid4().hex[:10]}"
    register_teacher(client, username=username, password="pw123456")
    token = login(client, username, "pw123456").json()["access_token"]
    with DBSession(engine) as s:
        teacher_id = s.exec(select(User.id).where(User.username == username)).one()
    return token, teacher_id


class TestKnowledgePoints:
    def test_scope_without_material_is_empty_and_explained(self, client, solo):
        """没上传过教材的范围必须是空的，并且说清**为什么空**（ADR-0065）。

        回归背景：原先这里由骨架目录兜底——一份教材都没传的「3 年级数学」也列出
        十几条预置知识点，教师勾选确认拿到的却是和学生无关的空目录。这里钉住
        「没有教材就是没有知识点」，并顺带钉住空态文案必须点出下一步做什么
        （ADR-0051：空态要回答「为什么空」+「下一步做什么」）。
        """
        token, _ = solo
        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=3",
            headers=auth_headers(token),
        )
        assert r.status_code == 200
        body = r.json()
        assert body["items"] == []
        assert "还没有上传过教材" in body["notice"], "空列表本身不解释任何事"
        assert "资料库" in body["notice"], "要指出下一步去哪"

    def test_uploaded_material_without_kps_is_distinguished(
        self, client, solo, upload_root
    ):
        """传了教材但没识别出知识点 ≠ 没传教材，两种空必须给不同说法。

        前者要多做一步「重新提取」，后者要先去上传——文案说错了，教师照着做就是
        白跑一趟。
        """
        token, _ = solo
        folder = _create_folder(
            client, token, name="三年级数学", subject="数学", grade=3
        )
        _upload(
            client,
            token,
            filename="单元练习.txt",
            content="一些正文。".encode(),
            folder_id=folder["id"],
        )
        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=3",
            headers=auth_headers(token),
        )
        assert r.status_code == 200
        body = r.json()
        assert body["items"] == []
        assert "1 份教材" in body["notice"], "应说明资料存在但尚未识别出知识点"
        assert "重新提取" in body["notice"]

    def test_legacy_skeleton_rows_are_hidden(self, client, solo):
        """历史遗留的 skeleton 行（当年教师确认过的预置条目）不再出现在目录里。

        为什么不删库：这些行可能挂着交互讲解模板（scenes），删除不可逆。屏蔽是
        可逆的——哪天要恢复，去掉这一行过滤即可。
        """
        from sqlmodel import Session as DBSession

        from app.core.db import engine
        from app.db.models import KnowledgePoint

        token, teacher_id = solo
        with DBSession(engine) as s:
            s.add(
                KnowledgePoint(
                    teacher_id=teacher_id,
                    subject="数学",
                    grade=6,
                    semester="上学期",
                    name="分数加减法",
                    status="curated",
                    source="skeleton",
                )
            )
            s.commit()

        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=6",
            headers=auth_headers(token),
        )
        assert r.status_code == 200
        assert [i["name"] for i in r.json()["items"]] == []

    def test_scopes_only_lists_uploaded_materials(self, client, upload_root):
        """范围清单 = 实际上传过教材的 (学科, 年级, 学期)（ADR-0065）。

        教师的提问原型：「我只传了 4 年级数学上下册，那知识点管理里就该只有 4 年级
        数学」。学期必须落在文件名推断出的那个值上——本学期口径与知识点诞生时不一
        致，下拉里就会出现「4 年级数学上学期」点进去却空空如也的死入口。
        """
        def _scopes(token: str) -> dict:
            r = client.get(
                "/api/v1/materials/knowledge-points/scopes",
                headers=auth_headers(token),
            )
            assert r.status_code == 200, r.text
            return r.json()

        _new = lambda username: (  # noqa: E731  测试内的小工具，省三段重复注册代码
            register_teacher(client, username=username, password="pw123456"),
            login(client, username, "pw123456").json()["access_token"],
        )[1]

        mine = _new("scope_upper_lower")
        assert _scopes(mine)["scopes"] == [], "前置：新账号还没传资料"

        folder = _create_folder(client, mine, name="四年级数学", subject="数学", grade=4)
        for filename in ("四年级上册.txt", "四年级下册.txt"):
            _upload(
                client,
                mine,
                filename=filename,
                content="教材正文。".encode(),
                folder_id=folder["id"],
            )

        body = _scopes(mine)
        scopes = {(s["subject"], s["grade"], s["semester"]) for s in body["scopes"]}
        assert scopes == {
            ("数学", 4, "上学期"),
            ("数学", 4, "下学期"),
        }, "只应有真实传过教材的范围，且学期靠文件名（上/下册）推断出来"
        assert body["unscoped_count"] == 0

    def test_scopes_reports_unscoped_materials(self, client, upload_root):
        """学科 / 年级缺失的资料归不到任何范围，必须**计数回报**。

        不回报的话，教师传了资料却在下拉里找不到对应年级，第一反应是「上传丢了」。
        """
        register_teacher(client, username="scope_unscoped", password="pw123456")
        token = login(client, "scope_unscoped", "pw123456").json()["access_token"]

        def _unscoped() -> int:
            r = client.get(
                "/api/v1/materials/knowledge-points/scopes",
                headers=auth_headers(token),
            )
            assert r.status_code == 200, r.text
            return r.json()["unscoped_count"]

        baseline = _unscoped()
        # 不挂任何目录 → 没有学科 / 年级可继承
        _upload(
            client, token, filename="杂记.txt", content="没有目录归属。".encode()
        )
        assert _unscoped() == baseline + 1

    def test_scopes_merges_count_and_isolates_by_teacher(self, client, upload_root):
        """同一范围的多份资料**合并计数**；范围清单按教师隔离。

        合并而不是逐条列出：下拉里出现两条「2 年级语文 上学期」等于把目录层级混进
        了范围维度，教师没法判断该选哪个。
        """
        register_teacher(client, username="scope_merge", password="pw123456")
        token = login(client, "scope_merge", "pw123456").json()["access_token"]
        register_teacher(client, username="scope_other", password="pw123456")
        other = login(client, "scope_other", "pw123456").json()["access_token"]

        folder = _create_folder(client, token, name="二年级语文", subject="语文", grade=2)
        for name in ("识字一.txt", "课文.txt"):
            _upload(
                client,
                token,
                filename=name,
                content="识字。".encode(),
                folder_id=folder["id"],
            )

        r = client.get(
            "/api/v1/materials/knowledge-points/scopes", headers=auth_headers(token)
        )
        assert r.status_code == 200
        scopes = r.json()["scopes"]
        assert len(scopes) == 1, "同 (学科,年级,学期) 要合并计数而不是逐条列出"
        assert scopes[0]["material_count"] == 2

        # 别家教师看不到这家的教材范围
        r = client.get(
            "/api/v1/materials/knowledge-points/scopes", headers=auth_headers(other)
        )
        assert r.status_code == 200 and r.json()["scopes"] == []

    def test_semester_scope_union_vs_exact(self, client, solo):
        """学期维度（ADR-0061）：不限学期 = 并集；限定学期 = 精确匹配。

        回归背景：早期实现对 ``semester=''`` 也做精确匹配，而资料涌现的知识点几乎
        都带「上/下学期」——于是发布任务表单默认态（不限学期）永远捞不到东西，
        教师看到的就是「知识点不随学期切换」。这里钉住两态语义。

        知识点插库为 ``emerged``：ADR-0065 起确认接口不再代建条目，目录里的每一行
        都必须能追溯到某份具体的教材。
        """
        from sqlmodel import Session as DBSession

        from app.core.db import engine
        from app.db.models import KnowledgePoint

        token, teacher_id = solo
        with DBSession(engine) as s:
            for semester, name in (
                ("上学期", "上册专属点"),
                ("下学期", "下册专属点"),
            ):
                s.add(
                    KnowledgePoint(
                        teacher_id=teacher_id,
                        subject="数学",
                        grade=4,
                        semester=semester,
                        name=name,
                        status="pending",
                        source="emerged",
                    )
                )
            s.commit()

        def _names(semester: str | None) -> list[str]:
            url = "/api/v1/materials/knowledge-points?subject=数学&grade=4"
            if semester is not None:
                url += f"&semester={semester}"
            r = client.get(url, headers=auth_headers(token))
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
            headers=auth_headers(token),
        )
        by_name = {i["name"]: i.get("semester") for i in r.json()["items"]}
        assert by_name["上册专属点"] == "上学期"
        assert by_name["下册专属点"] == "下学期"

    def test_confirm_ignores_names_not_in_directory(self, client, solo):
        """确认接口不再代建条目（ADR-0065）。

        知识点只认已上传教材里涌现的那些，所以勾一个库里没有的名字不该凭空造一行
        ——目录里能勾到的一定是已有行，留着「名下无行就新建」就是给「手动录入知识
        点」留后门。
        """
        token, _ = solo
        r = client.post(
            "/api/v1/materials/knowledge-points/confirm",
            headers=auth_headers(token),
            json={"names": ["天外飞来的点"], "subject": "数学", "grade": 8},
        )
        assert r.status_code == 200 and r.json()["confirmed"] == 0
        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=8",
            headers=auth_headers(token),
        )
        assert r.json()["items"] == []

    def test_confirm_flips_all_semester_variants(self, client, solo):
        """确认按概念名跨学期生效（修复同名待审残留）。

        同一概念「图形的运动」按学期拆成 上学期(pending) + 下学期(pending) 两行；
        在「整学年」视图确认后，两行都应转正，而不是只翻当前筛选学期那行（旧实现按
        semester 精确 find，导致同名其它学期的待审永远翻不动）。学期不再允许空
        （2026-10-05 决策），故以两个具体学期模拟「重名两行」。
        """
        from sqlmodel import Session as DBSession

        from app.core.db import engine
        from app.db.models import KnowledgePoint

        token, teacher_id = solo
        with DBSession(engine) as s:
            for sem in ("上学期", "下学期"):
                s.add(
                    KnowledgePoint(
                        teacher_id=teacher_id,
                        subject="数学",
                        grade=3,
                        semester=sem,
                        name="图形的运动",
                        status="pending",
                        source="emerged",
                    )
                )
            s.commit()

        # 在「整学年」视图确认该概念（semester 默认 ''）
        r = client.post(
            "/api/v1/materials/knowledge-points/confirm",
            headers=auth_headers(token),
            json={"names": ["图形的运动"], "subject": "数学", "grade": 3},
        )
        assert r.status_code == 200, r.text
        assert r.json()["confirmed"] == 2

        # 两条同名数据都应已转正（不再并存「待审 + 已转正」）
        r = client.get(
            "/api/v1/materials/knowledge-points?subject=数学&grade=3",
            headers=auth_headers(token),
        )
        assert r.status_code == 200, r.text
        rows = [
            i
            for i in r.json()["items"]
            if i["name"] == "图形的运动" and i["id"] is not None
        ]
        assert {i["semester"] for i in rows} == {"上学期", "下学期"}
        assert all(i["status"] == "curated" for i in rows)


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
    def test_vectorize_requires_config(self, client, ptoken, uploaded_mat_id, monkeypatch):
        # 显式置 none：本地 .env 可能把 EMBEDDING_PROVIDER 设成 ollama（走 failed 分支），
        # 这里要钉住的是「完全未配置 → 500 + LLM_UNAVAILABLE」这条路径，不受 .env 影响。
        monkeypatch.setattr(
            "app.features.materials.indexing.settings.EMBEDDING_PROVIDER", "none"
        )
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
    def test_hybrid_retrieval_and_filter(self, client, solo, upload_root, db, monkeypatch):
        """向量化后经 build_retriever('vector') 检索：dense+词法融合，快照带资料名。

        用独立账号（solo）而非共享 ptoken：避免全量里其它用例给 mat_teacher 向量化出的
        「数学/3 年级」片段混进候选集，把「鸡兔」挤下首命中（历史上全量红、单跑绿的成因）。
        """
        token, teacher_id = solo
        folder = _create_folder(client, token, name="数学三上", subject="数学", grade=3)

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
            r = _upload(client, token, filename=name, content=content.encode(), folder_id=folder["id"])
            mat_ids.append(r.json()["material"]["id"])
        for mid in mat_ids:
            r = client.post(f"/api/v1/materials/{mid}/vectorize", headers=auth_headers(token))
            assert r.json()["index_state"] == "ready", r.text

        # 切到 vector 检索：查询向量指向「鸡兔」簇
        monkeypatch.setattr("app.core.config.settings.RETRIEVER_PROVIDER", "vector")

        async def q_embed(texts):
            return [[1.0, 0.0, 0.0, 0.0] for _ in texts]

        monkeypatch.setattr("app.features.materials.retrieval.embed_texts", q_embed)

        from app.domain.retriever import build_retriever

        retriever = build_retriever(session=db, teacher_id=teacher_id)
        chunks = retriever.retrieve(subject="数学", grade=3, knowledge_point="鸡兔同笼", query="鸡兔同笼")
        assert chunks, "向量+词法双路不应为空"
        assert all(c.source == "vector" for c in chunks)
        # RRF 融合后首命中是 dense+词法双高分的「鸡兔」片段，快照带资料名
        assert chunks[0].source_name == "鸡兔同笼.txt"
        assert "鸡兔同笼" in chunks[0].content

    def test_version_mismatch_excluded(self, client, solo, upload_root, db, monkeypatch):
        """版本戳双保险：embed_model 与当前配置不符的 chunk 不参与检索（stale 语义）。

        独立账号 + 自管向量化：全量里其它用例给共享账号留下的 4 维假向量片段，
        会与本例用「真实 embed_texts」查出的高维向量维度不一致（zip strict 崩），
        故这里也用同一套假向量，维度自洽；同时避免混入别家的资料片段。
        """
        from app.db.models import MaterialChunk
        from app.features.materials import repository as repo
        from app.features.materials.retrieval import VectorKnowledgeRetriever

        token, teacher_id = solo
        folder = _create_folder(client, token, name="数学三上", subject="数学", grade=3)
        r = _upload(
            client,
            token,
            filename="乘法.txt",
            content=("两位数乘法。先算个位，再算十位，满十进一。" * 30).encode(),
            folder_id=folder["id"],
        )
        old_id = r.json()["material"]["id"]

        # 假向量：始终可用、维度与查询端一致（4 维）
        async def fake_embed(texts):
            return [[1.0, 0.0, 0.0, 0.0] for _ in texts]

        monkeypatch.setattr(
            "app.features.materials.indexing.settings.EMBEDDING_PROVIDER", "ollama"
        )
        monkeypatch.setattr("app.features.materials.indexing.embed_texts", fake_embed)
        r = client.post(
            f"/api/v1/materials/{old_id}/vectorize", headers=auth_headers(token)
        )
        assert r.json()["index_state"] == "ready", r.text

        mats = repo.list_materials(db, teacher_id=teacher_id, folder_id=None)
        assert mats, "前置：已有已上传资料"
        old = mats[0]
        db.add(
            MaterialChunk(
                teacher_id=teacher_id,
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
        # 查询端也走同一假向量，避免维度不一致触发 _cosine(zip strict) 崩溃
        monkeypatch.setattr("app.features.materials.retrieval.embed_texts", fake_embed)
        retriever = VectorKnowledgeRetriever(db, teacher_id)
        chunks = retriever.retrieve(
            subject=old.subject or "数学",
            grade=old.grade or 3,
            knowledge_point="任意",
            query="孤儿片段",
        )
        assert all("旧模型的孤儿片段" not in c.content for c in chunks)
