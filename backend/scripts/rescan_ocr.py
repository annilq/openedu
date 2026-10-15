"""资料库 OCR 重扫（ADR-0092 落地收尾）。

背景：当初入库时 rapidocr / pymupdf 尚未安装，扫描页被解析器退化为
「检测到 N 页疑似扫描页，但 OCR 组件未安装」告警，且那几页文字留空。
现已 `uv sync` 装上 OCR 依赖，本脚本对「仍带 OCR 未安装告警」的资料：

1. 从落盘 storage_key 读回 PDF 字节；
2. 重新 parse_material（此时 RapidOCR 真实可用，扫描页被识别回填）；
3. 更新 material.text + parse_meta（告警随之变为「已自动 OCR 识别」）；
4. 调 vectorize_material 重建 chunks，使 recovered 文字进入检索。

保留原 material id，不删除重建。用法：
    cd backend && no_proxy=127.0.0.1,localhost,::1 ./scripts/rescan_ocr.py
"""

from __future__ import annotations

import asyncio
import sys
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlmodel import Session, select  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.db import engine  # noqa: E402
from app.db.models import Material, Role, User  # noqa: E402
from app.features.materials import indexing  # noqa: E402
from app.features.materials.parser import parse_material  # noqa: E402
from app.features.materials.repository import get_owned_material  # noqa: E402


def get_teacher_id(session: Session) -> uuid.UUID:
    user = session.exec(select(User).where(User.username == "annilq")).first()
    if user is None:
        user = session.exec(select(User).where(User.role == Role.TEACHER)).first()
    if user is None:
        raise SystemExit("数据库里没有教师账号")
    return user.id


def needs_ocr_rescan(material: Material) -> bool:
    meta = material.parse_meta or {}
    warns = meta.get("warnings", [])
    return (
        meta.get("scan_pages", 0) > 0
        and meta.get("ocr_pages", 0) == 0
        and any("OCR 组件未安装" in w for w in warns)
    )


async def main() -> None:
    with Session(engine) as session:
        teacher_id = get_teacher_id(session)
        print(f"teacher_id={teacher_id}  ROOT={settings.MATERIAL_UPLOAD_ROOT}")
        print("=" * 72)

        materials = session.exec(select(Material)).all()
        targets = [m for m in materials if needs_ocr_rescan(m)]
        print(f"待重扫资料：{len(targets)} / 共 {len(materials)}")
        print("=" * 72)

        ok = fail = 0
        for m in targets:
            path = Path(settings.MATERIAL_UPLOAD_ROOT) / m.storage_key
            if not path.exists():
                print(f"[缺文件] {m.name}  skip ({path})")
                fail += 1
                continue
            data = path.read_bytes()
            t0 = time.time()
            try:
                report = parse_material(filename=m.name, data=data)
            except Exception as e:  # noqa: BLE001
                print(f"[解析异常] {m.name}  —— {type(e).__name__}: {e}")
                fail += 1
                continue

            # 更新文本 + 解析元数据（告警随之刷新）；先落库，确保 UI 告警即时清除
            m.text = report.text
            m.parse_meta = report.to_meta()
            session.add(m)
            session.commit()
            session.refresh(m)

            # 重建向量（用 recovered 文字）
            try:
                material = await indexing.vectorize_material(
                    session, teacher_id=teacher_id, material_id=m.id
                )
            except Exception as e:  # noqa: BLE001
                print(f"[向量化异常] {m.name}  —— {type(e).__name__}: {e}")
                fail += 1
                continue

            new_meta = material.parse_meta or {}
            new_warns = new_meta.get("warnings", [])
            print(
                f"[{material.index_state}] {m.name}\n"
                f"    scan={new_meta.get('scan_pages')} ocr={new_meta.get('ocr_pages')} "
                f"text={len(report.text)} chars  ({time.time()-t0:.1f}s)\n"
                f"    告警: {' | '.join(new_warns) if new_warns else '(无)'}"
            )
            if material.index_state == "ready":
                ok += 1
            else:
                fail += 1

        print("=" * 72)
        print(f"OCR 重扫完成：成功 {ok} · 失败 {fail}")


if __name__ == "__main__":
    asyncio.run(main())
