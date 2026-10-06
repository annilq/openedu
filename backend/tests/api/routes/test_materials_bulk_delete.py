"""资料库多选删除（ADR-0055 补充）：批量删资料 + 孤儿知识点清理 + 知识点批量删除。

为什么单独成文件：考点是「删除的连带边界」——什么该被带走、什么必须留下，
与上传/向量化那条主线正交。写在一起会让主线的用例表越来越长，反而看不清边界。

删除资料时**能不能顺带删知识点**是本文件的核心议题（见 ``TestCascadePruning``）：
两者之间没有外键，只有名字字符串，而同一个知识点名字会被多份资料共享，
所以「删除资料 → 删除其知识点」不是天然成立的，必须按作用域算清楚。
"""

from __future__ import annotations

import io
import uuid

import pytest
from sqlmodel import Session as DBSession
from sqlmodel import select

from app.core.db import engine
from app.db.models import KnowledgePoint, Material, MaterialChunk, User
from app.db.models.material import (
    KP_SOURCE_EMERGED,
    KP_SOURCE_SKELETON,
    KP_STATUS_CURATED,
    KP_STATUS_PENDING,
)
from tests.utils.user import auth_headers, login, register_teacher


@pytest.fixture()
def ptoken(client):
    register_teacher(client, username="matdel_teacher", password="pw123456")
    return login(client, "matdel_teacher", "pw123456").json()["access_token"]


@pytest.fixture()
def teacher_id() -> uuid.UUID:
    with DBSession(engine) as s:
        return s.exec(
            select(User.id).where(User.username == "matdel_teacher")
        ).one()


def _upload(client, token, *, filename: str, content: bytes, folder_id=None) -> str:
    data = {"file": (filename, io.BytesIO(content))}
    fields = {"folder_id": folder_id} if folder_id else {}
    r = client.post(
        "/api/v1/materials/upload", headers=auth_headers(token), files=data, data=fields
    )
    assert r.status_code == 200, r.text
    return r.json()["material"]["id"]


def _seed_material(
    *,
    teacher_id: uuid.UUID,
    name: str,
    knowledge_points: list[str],
    subject: str = "数学",
    grade: int = 3,
    semester: str = "上学期",
) -> Material:
    """直接落一条带知识点清单的资料。

    绕开 AI 提取：那条路径需模型参与，而本文件只关心删除的连带关系——
    ``knowledge_points`` 的内容由测试直接指定，边界才是可控的。
    """
    with DBSession(engine) as s:
        mat = Material(
            teacher_id=teacher_id,
            name=name,
            storage_key=f"{teacher_id}/{uuid.uuid4()}.txt",
            size_bytes=10,
            text="占位正文",
            subject=subject,
            grade=grade,
            semester=semester,
            knowledge_points=knowledge_points,
        )
        s.add(mat)
        s.commit()
        s.refresh(mat)
        return mat


def _seed_kp(
    *,
    teacher_id: uuid.UUID,
    name: str,
    subject: str = "数学",
    grade: int = 3,
    semester: str = "上学期",
    status: str = KP_STATUS_PENDING,
    source: str = KP_SOURCE_EMERGED,
) -> uuid.UUID:
    with DBSession(engine) as s:
        kp = KnowledgePoint(
            teacher_id=teacher_id,
            subject=subject,
            grade=grade,
            semester=semester,
            name=name,
            status=status,
            source=source,
        )
        s.add(kp)
        s.commit()
        s.refresh(kp)
        return kp.id


def _kp_names(teacher_id: uuid.UUID) -> set[str]:
    with DBSession(engine) as s:
        return set(
            s.exec(select(KnowledgePoint.name).where(
                KnowledgePoint.teacher_id == teacher_id
            )).all()
        )


def _material_names(teacher_id: uuid.UUID) -> set[str]:
    with DBSession(engine) as s:
        return set(
            s.exec(select(Material.name).where(
                Material.teacher_id == teacher_id
            )).all()
        )


class TestBulkDeleteMaterials:
    def test_only_selected_are_deleted(self, client, ptoken, teacher_id):
        _upload(client, ptoken, filename="保留.txt", content="保留保留保留".encode())
        gone1 = _upload(client, ptoken, filename="甲.txt", content="甲甲甲甲甲甲".encode())
        gone2 = _upload(client, ptoken, filename="乙.txt", content="乙乙乙乙乙乙".encode())

        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [gone1, gone2]},
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["deleted_count"] == 2

        remaining = _material_names(teacher_id)
        assert "保留.txt" in remaining
        assert "甲.txt" not in remaining and "乙.txt" not in remaining

    def test_duplicate_ids_counted_once(self, client, ptoken):
        gone = _upload(client, ptoken, filename="重名.txt", content="丙丙丙丙丙丙".encode())
        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [gone, gone]},
        )
        assert r.status_code == 200, r.text
        assert r.json()["deleted_count"] == 1, "重复 id 不该让计数虚高"

    def test_other_teacher_material_403(self, client, ptoken):
        register_teacher(client, username="matdel_other", password="pw123456")
        other = login(client, "matdel_other", "pw123456").json()["access_token"]
        mine = _upload(client, ptoken, filename="我的.txt", content="我的我的我的".encode())
        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(other),
            json={"ids": [mine]},
        )
        assert r.status_code == 403, "删别人的资料必须是归属错误，而不是静默成功"
        # 越权不得产生副作用
        r = client.get("/api/v1/materials", headers=auth_headers(ptoken))
        assert r.status_code == 200
        assert any(m["name"] == "我的.txt" for m in r.json())

    def test_chunks_are_removed_together(self, client, ptoken, teacher_id):
        """资料删了，它的片段必须跟着删——孤儿 chunk 会被检索静默召回。"""
        mat = _seed_material(
            teacher_id=teacher_id, name="有片段.txt", knowledge_points=["周长公式"]
        )
        with DBSession(engine) as s:
            for seq in range(3):
                s.add(
                    MaterialChunk(
                        teacher_id=teacher_id,
                        material_id=mat.id,
                        seq=seq,
                        content=f"片段{seq}",
                        subject="数学",
                        grade=3,
                    )
                )
            s.commit()

        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(mat.id)]},
        )
        assert r.status_code == 200, r.text
        assert r.json()["chunks_removed"] == 3

        with DBSession(engine) as s:
            assert (
                s.exec(
                    select(MaterialChunk).where(
                        MaterialChunk.material_id == mat.id
                    )
                ).all()
                == []
            )


class TestCascadePruning:
    """删除资料时的知识点连带口径：只收回「无人认领」的待审涌现点。"""

    def test_orphan_pending_point_is_pruned(self, client, ptoken, teacher_id):
        mat = _seed_material(
            teacher_id=teacher_id, name="唯一来源.txt", knowledge_points=["两位数乘法"]
        )
        _seed_kp(teacher_id=teacher_id, name="两位数乘法", status=KP_STATUS_PENDING)

        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(mat.id)], "cascade_knowledge_points": True},
        )
        assert r.status_code == 200, r.text
        assert r.json()["knowledge_points_removed"] == 1
        assert "两位数乘法" not in _kp_names(teacher_id)

    def test_default_off(self, client, ptoken, teacher_id):
        """不带开关 = 不碰知识点：删除的副作用必须显式要求才发生。"""
        mat = _seed_material(
            teacher_id=teacher_id, name="默认不级联.txt", knowledge_points=["面积单位"]
        )
        _seed_kp(teacher_id=teacher_id, name="面积单位", status=KP_STATUS_PENDING)

        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(mat.id)]},
        )
        assert r.status_code == 200, r.text
        assert r.json()["knowledge_points_removed"] == 0
        assert "面积单位" in _kp_names(teacher_id)

    def test_keeps_point_referenced_by_another_material(
        self, client, ptoken, teacher_id
    ):
        """同名的另一份资料还在 → 知识点有别的来源，不能删。"""
        to_delete = _seed_material(
            teacher_id=teacher_id, name="要删的.txt", knowledge_points=["分数的意义"]
        )
        _seed_material(
            teacher_id=teacher_id, name="留存的.txt", knowledge_points=["分数的意义"]
        )
        _seed_kp(teacher_id=teacher_id, name="分数的意义", status=KP_STATUS_PENDING)

        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(to_delete.id)], "cascade_knowledge_points": True},
        )
        assert r.status_code == 200, r.text
        assert r.json()["knowledge_points_removed"] == 0
        assert "分数的意义" in _kp_names(teacher_id)

    def test_keeps_curated_point(self, client, ptoken, teacher_id):
        """教师确认过（curated）的知识点是教师的资产：删资料不该顺手抹掉。"""
        mat = _seed_material(
            teacher_id=teacher_id, name="已确认.txt", knowledge_points=["圆的周长"]
        )
        _seed_kp(teacher_id=teacher_id, name="圆的周长", status=KP_STATUS_CURATED)

        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(mat.id)], "cascade_knowledge_points": True},
        )
        assert r.status_code == 200, r.text
        assert r.json()["knowledge_points_removed"] == 0
        assert "圆的周长" in _kp_names(teacher_id)

    def test_keeps_skeleton_point(self, client, ptoken, teacher_id):
        """骨架（教师自编）与资料无关，永远不该被资料删除带走。"""
        mat = _seed_material(
            teacher_id=teacher_id, name="骨架旁.txt", knowledge_points=["分数的加减法"]
        )
        _seed_kp(
            teacher_id=teacher_id,
            name="分数的加减法",
            status=KP_STATUS_PENDING,
            source=KP_SOURCE_SKELETON,
        )

        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(mat.id)], "cascade_knowledge_points": True},
        )
        assert r.status_code == 200, r.text
        assert r.json()["knowledge_points_removed"] == 0
        assert "分数的加减法" in _kp_names(teacher_id)

    def test_semester_scope_is_respected(self, client, ptoken, teacher_id):
        """下学期那份不动：学期是独立的第四维（各自配讲解模板）。"""
        mat = _seed_material(
            teacher_id=teacher_id,
            name="上册.txt",
            knowledge_points=["位置与方向"],
            semester="上学期",
        )
        _seed_kp(teacher_id=teacher_id, name="位置与方向", semester="上学期")
        _seed_kp(teacher_id=teacher_id, name="位置与方向", semester="下学期")

        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(mat.id)], "cascade_knowledge_points": True},
        )
        assert r.status_code == 200, r.text
        assert r.json()["knowledge_points_removed"] == 1

        with DBSession(engine) as s:
            rows = s.exec(
                select(KnowledgePoint.semester).where(
                    KnowledgePoint.teacher_id == teacher_id,
                    KnowledgePoint.name == "位置与方向",
                )
            ).all()
        assert rows == ["下学期"]

    def test_cascade_does_not_touch_other_teacher(self, client, ptoken, teacher_id):
        """清理只按自己名下算：别人家的同名知识点既不算「仍被引用」也不被删。"""
        register_teacher(client, username="matdel_kp_other", password="pw123456")
        with DBSession(engine) as s:
            other_id = s.exec(
                select(User.id).where(User.username == "matdel_kp_other")
            ).one()

        mat = _seed_material(
            teacher_id=teacher_id, name="自家.txt", knowledge_points=["百分数"]
        )
        _seed_kp(teacher_id=teacher_id, name="百分数", status=KP_STATUS_PENDING)
        _seed_kp(teacher_id=other_id, name="百分数", status=KP_STATUS_PENDING)

        r = client.post(
            "/api/v1/materials/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(mat.id)], "cascade_knowledge_points": True},
        )
        assert r.status_code == 200, r.text
        assert r.json()["knowledge_points_removed"] == 1
        assert "百分数" not in _kp_names(teacher_id)
        assert "百分数" in _kp_names(other_id), "别家的同名知识点必须原样保留"


class TestBulkDeleteKnowledgePoints:
    def test_delete_selected_points(self, client, ptoken, teacher_id):
        a = _seed_kp(teacher_id=teacher_id, name="要删点甲")
        _seed_kp(teacher_id=teacher_id, name="保留点乙")

        r = client.post(
            "/api/v1/materials/knowledge-points/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(a)]},
        )
        assert r.status_code == 200, r.text
        assert r.json()["deleted_count"] == 1

        names = _kp_names(teacher_id)
        assert "要删点甲" not in names
        assert "保留点乙" in names

    def test_foreign_ids_are_skipped(self, client, ptoken, teacher_id):
        """越权 id 静默跳过（不动他人数据），且不谎报成功。"""
        register_teacher(client, username="matdel_kp_other2", password="pw123456")
        with DBSession(engine) as s:
            other_id = s.exec(
                select(User.id).where(User.username == "matdel_kp_other2")
            ).one()
        foreign = _seed_kp(teacher_id=other_id, name="别家的点")

        r = client.post(
            "/api/v1/materials/knowledge-points/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [str(foreign), "00000000-0000-0000-0000-000000000000"]},
        )
        assert r.status_code == 200, r.text
        assert r.json()["deleted_count"] == 0
        assert "别家的点" in _kp_names(other_id)

    def test_delete_curated_point_end_to_end(self, client, ptoken, teacher_id):
        """端到端：教材涌现 → 教师确认转正 → 再删掉（知识点管理页「删除选中」主链路）。

        知识点由 `_seed_kp` 以 ``emerged`` 落库，而不是靠 confirm 接口新建——
        ADR-0065 起确认只翻转已有行的状态，不再代建条目（知识点必须能追溯到教材）。
        """
        _seed_kp(
            teacher_id=teacher_id,
            name="临时知识点",
            status=KP_STATUS_PENDING,
            source=KP_SOURCE_EMERGED,
        )
        client.post(
            "/api/v1/materials/knowledge-points/confirm",
            headers=auth_headers(ptoken),
            json={"names": ["临时知识点"], "subject": "数学", "grade": 3},
        )
        rows = [
            i
            for i in client.get(
                "/api/v1/materials/knowledge-points?subject=数学&grade=3",
                headers=auth_headers(ptoken),
            ).json()["items"]
            if i["id"] is not None and i["name"] == "临时知识点"
        ]
        assert rows and rows[0]["status"] == "curated", "前置：确认后应已转正"

        r = client.post(
            "/api/v1/materials/knowledge-points/bulk-delete",
            headers=auth_headers(ptoken),
            json={"ids": [rows[0]["id"]]},
        )
        assert r.status_code == 200, r.text
        assert r.json()["deleted_count"] == 1
        assert "临时知识点" not in _kp_names(teacher_id)
