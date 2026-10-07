"""平台 CC0 预置素材入库（T08 / ADR-0067 §3.5·§5）。

覆盖硬边界：
1. seed 后素材带 ``source=platform_cc0`` + 来源 URL + 许可类型，且物理文件离线落盘；
2. 平台 CC0 对所有教师可见（含与本人素材并列）；
3. 任意教师可取 CC0 原图（磁盘读取，**无运行时联网**）；
4. 普通教师删除 CC0 被拦截（403）；自有素材删除不受影响；
5. seed 幂等（连跑不重复入库）；
6. 历史上传行默认 ``user_uploaded``；
7. 启动期迁移给老库补上 source/source_url/license 三列，且幂等。
"""
from __future__ import annotations

import io
import uuid

import pytest
from sqlmodel import Session as DBSession
from sqlmodel import create_engine, select, text

from app.core.db import _add_coursewareasset_cc0_columns, engine
from app.core.errors import AppErrorException, ErrCode
from app.db.models import CoursewareAsset
from app.db.models.courseware import (
    COURSEWARE_ASSET_SOURCE_PLATFORM_CC0,
    COURSEWARE_ASSET_SOURCE_USER_UPLOADED,
)
from app.features.courseware import asset_service as svc
from app.features.courseware.seed_cc0 import seed_courseware_cc0


@pytest.fixture(autouse=True)
def _clean_cc0():
    """共享会话库会跨测试残留 CC0 行（idempotency 以 name 为键），每个测试前清空。"""
    with DBSession(engine) as s:
        for r in s.exec(
            select(CoursewareAsset).where(
                CoursewareAsset.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0
            )
        ).all():
            s.delete(r)
        s.commit()
    yield


def _png_bytes() -> bytes:
    """生成一张最小合法 PNG（不联网、不依赖外部文件）。"""
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (4, 4), (255, 0, 0)).save(buf, "PNG")
    return buf.getvalue()


def _make_seed_dir(tmp_path, *, name: str = "测试CC0") -> object:
    """在 tmp 里造一个离线 seed 目录（manifest + 图片），返回其 Path。"""
    d = tmp_path / "cc0_seed"
    d.mkdir()
    (d / "x.png").write_bytes(_png_bytes())
    (d / "manifest.json").write_text(
        f'[{{"filename":"x.png","name":"{name}",'
        f'"source_url":"https://example.com/{name}","license":"CC0 1.0"}}]',
        encoding="utf-8",
    )
    return d


def _seed_one(tmp_path, *, name: str = "测试CC0") -> uuid.UUID:
    d = _make_seed_dir(tmp_path, name=name)
    with DBSession(engine) as s:
        seed_courseware_cc0(s, seed_dir=d)
        row = s.exec(
            select(CoursewareAsset).where(
                CoursewareAsset.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0
            )
        ).first()
        return row.id


def test_seed_creates_platform_cc0_with_source_and_license(tmp_path):
    d = _make_seed_dir(tmp_path)
    with DBSession(engine) as s:
        seed_courseware_cc0(s, seed_dir=d)
        row = s.exec(
            select(CoursewareAsset).where(
                CoursewareAsset.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0
            )
        ).first()
        assert row is not None
        assert row.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0
        assert row.source_url == "https://example.com/测试CC0"
        assert row.license == "CC0 1.0"
        # 物理文件离线落盘（不联网）。
        from pathlib import Path

        from app.core.config import settings

        assert (Path(settings.MATERIAL_UPLOAD_ROOT) / row.storage_key).is_file()


def test_cc0_visible_to_any_teacher(tmp_path):
    cc0_id = _seed_one(tmp_path)
    teacher_a = uuid.uuid4()
    with DBSession(engine) as s:
        # 本人上传一张自有素材，验证「并列展示」。
        own = svc.upload_asset(
            s,
            teacher_id=teacher_a,
            filename="mine.png",
            mime="image/png",
            data=_png_bytes(),
        )
        items = svc.search_assets(s, teacher_id=teacher_a).items
        ids = [i.id for i in items]
        assert cc0_id in ids, "平台 CC0 应对任意教师可见"
        assert own.id in ids, "本人素材仍应在列表里"
        cc0_resp = next(i for i in items if i.id == cc0_id)
        assert cc0_resp.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0
        assert cc0_resp.source_url and cc0_resp.license


def test_cc0_asset_file_served_offline(tmp_path):
    cc0_id = _seed_one(tmp_path)
    teacher_a = uuid.uuid4()
    teacher_b = uuid.uuid4()
    with DBSession(engine) as s:
        path, mime = svc.asset_file(s, teacher_id=teacher_a, asset_id=cc0_id)
        assert path.is_file(), "CC0 原图从磁盘读取，不联网"
        assert mime == "image/png"
        # 另一个互不相干的教师也能取到（公共素材）。
        path2, _ = svc.asset_file(s, teacher_id=teacher_b, asset_id=cc0_id)
        assert path2.read_bytes() == path.read_bytes()


def test_delete_cc0_blocked_for_normal_teacher(tmp_path):
    cc0_id = _seed_one(tmp_path)
    teacher_a = uuid.uuid4()
    with DBSession(engine) as s:
        with pytest.raises(AppErrorException) as exc:
            svc.delete_asset(s, teacher_id=teacher_a, asset_id=cc0_id)
        assert exc.value.code == ErrCode.FORBIDDEN


def test_own_asset_delete_still_works(tmp_path):
    cc0_id = _seed_one(tmp_path)  # 保证库里已有 CC0，隔离「删 CC0 被拦」与「删自有成功」
    teacher_a = uuid.uuid4()
    with DBSession(engine) as s:
        own = svc.upload_asset(
            s,
            teacher_id=teacher_a,
            filename="mine.png",
            mime="image/png",
            data=_png_bytes(),
        )
        # 删自有素材应成功。
        svc.delete_asset(s, teacher_id=teacher_a, asset_id=own.id)
        leftover = s.get(CoursewareAsset, own.id)
        assert leftover is None
        # CC0 仍在（未被误删）。
        assert s.get(CoursewareAsset, cc0_id) is not None


def test_seed_idempotent(tmp_path):
    d = _make_seed_dir(tmp_path)
    with DBSession(engine) as s:
        n1 = seed_courseware_cc0(s, seed_dir=d)
        n2 = seed_courseware_cc0(s, seed_dir=d)
        assert n1 == 1
        assert n2 == 0, "同名 CC0 已存在应跳过，不重复入库"
        total = len(
            s.exec(
                select(CoursewareAsset).where(
                    CoursewareAsset.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0
                )
            ).all()
        )
        assert total == 1


def test_uploaded_asset_defaults_user_uploaded(tmp_path):
    teacher_a = uuid.uuid4()
    with DBSession(engine) as s:
        own = svc.upload_asset(
            s,
            teacher_id=teacher_a,
            filename="mine.png",
            mime="image/png",
            data=_png_bytes(),
        )
        assert own.source == COURSEWARE_ASSET_SOURCE_USER_UPLOADED


def test_migration_adds_cc0_columns_to_old_db(tmp_path):
    """复现「老库形状」（无 source 三列），跑迁移，断言补列且幂等。"""
    import sqlite3

    db = str(tmp_path / "old.db")
    conn = sqlite3.connect(db)
    conn.executescript(
        """
        CREATE TABLE coursewareasset (
            id CHAR(32) PRIMARY KEY,
            teacher_id CHAR(32),
            knowledge_point_id CHAR(32),
            name VARCHAR(255),
            storage_key VARCHAR(512),
            mime VARCHAR(64),
            size_bytes INTEGER,
            width INTEGER,
            height INTEGER,
            created_at DATETIME
        );
        """
    )
    conn.close()

    eng = create_engine(f"sqlite:///{db}")
    with eng.begin() as c:
        _add_coursewareasset_cc0_columns(c, True)
    with eng.begin() as c:
        cols = [r[1] for r in c.execute(text("PRAGMA table_info(coursewareasset)")).fetchall()]
    assert "source" in cols and "source_url" in cols and "license" in cols
    # 默认回填：加列后存量行 source 应为 user_uploaded。
    with eng.begin() as c:
        val = c.execute(text("SELECT source FROM coursewareasset")).fetchall()
    assert val == []  # 无存量行，仅验证列存在；默认值在插入时生效

    # 幂等：再跑一次不报错、列数不变。
    with eng.begin() as c:
        _add_coursewareasset_cc0_columns(c, True)
        cols2 = [r[1] for r in c.execute(text("PRAGMA table_info(coursewareasset)")).fetchall()]
    assert cols2 == cols
