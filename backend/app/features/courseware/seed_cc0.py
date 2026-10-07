"""平台 CC0 预置素材入库（T08 / ADR-0067 §3.5·§5）。

维护期一次性执行：读取 ``seeds/courseware_cc0/manifest.json`` + 同目录的离线图片，
把每张图作为 ``source=platform_cc0`` 的公共素材入库，记录来源 URL 与许可类型。

设计要点（硬边界）：

- **离线分发**：图片随仓库落地在 ``seeds/`` 目录，**不运行时联网**拉取；seed 本身是
  维护动作（部署 / 升级时跑一次），运行时只有磁盘读取，无任何网络调用。
- **对所有教师可见、不可删除**：入库时归属系统哨兵教师（[COURSEWARE_CC0_OWNER_ID]），
  由 ``asset_service.search_assets`` 的 ``source == platform_cc0`` 分支对所有教师放行，
  ``delete_asset`` 拦截删除。
- **幂等**：同名 CC0 素材已存在则跳过，连跑多次不重复入库、不破坏引用它的课件。

每个 manifest 条目：``filename``（同目录图片）、``name``（展示名）、``source_url``
（来源 URL，教师可溯源核授权）、``license``（许可类型，如 ``CC0 1.0``）。可选字段
``id``：显式指定资产 UUID，**用于需要稳定引用关系的场景**（如某课件 sections 按
``asset_id`` 引用该素材）。给定 ``id`` 时入库使用该值，保证重跑 seed 复现同一资产
行、不破坏既有引用；省略则 ``uuid4()`` 自动生成（向后兼容）。
"""
from __future__ import annotations

import json
import uuid
from pathlib import Path

from sqlmodel import Session, select

from app.db.models.courseware import (
    COURSEWARE_ASSET_SOURCE_PLATFORM_CC0,
    COURSEWARE_CC0_OWNER_ID,
    CoursewareAsset,
)
from app.features.courseware.asset_service import _probe_size, _store_file

# 默认 seed 目录：backend/seeds/courseware_cc0（manifest.json + 图片同目录）。
_SEED_DIR = (
    Path(__file__).resolve().parent.parent.parent.parent / "seeds" / "courseware_cc0"
)

_MIME_BY_EXT = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
}


def seed_courseware_cc0(session: Session, *, seed_dir: Path | None = None) -> int:
    """入库 manifest 里的 CC0 素材；返回本次新入库数量。已存在的同名素材跳过。

    ``seed_dir`` 可注入（测试用），默认走仓库内的 ``seeds/courseware_cc0``。
    """
    seed_dir = seed_dir or _SEED_DIR
    manifest_path = seed_dir / "manifest.json"
    if not manifest_path.is_file():
        raise FileNotFoundError(f"CC0 manifest 不存在：{manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    existing = {
        a.name
        for a in session.exec(
            select(CoursewareAsset).where(
                CoursewareAsset.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0
            )
        ).all()
    }

    added = 0
    for entry in manifest:
        name = entry["name"]
        if name in existing:
            continue
        data = (seed_dir / entry["filename"]).read_bytes()
        ext = Path(entry["filename"]).suffix.lower()
        mime = _MIME_BY_EXT.get(ext, "image/png")
        width, height = _probe_size(data)
        storage_key = _store_file(
            teacher_id=COURSEWARE_CC0_OWNER_ID,
            filename=entry["filename"],
            data=data,
        )
        asset_id = entry.get("id")
        asset = CoursewareAsset(
            id=uuid.UUID(asset_id) if asset_id else uuid.uuid4(),
            teacher_id=COURSEWARE_CC0_OWNER_ID,
            name=name,
            storage_key=storage_key,
            mime=mime,
            size_bytes=len(data),
            width=width,
            height=height,
            source=COURSEWARE_ASSET_SOURCE_PLATFORM_CC0,
            source_url=entry.get("source_url"),
            license=entry.get("license"),
        )
        session.add(asset)
        added += 1
    session.commit()
    return added
