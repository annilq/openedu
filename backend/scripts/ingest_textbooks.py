"""资料库批量入库 + 向量化（一次性 / 可复用）。

把 resources/ 下的教材 PDF 按文件名解析年级，按 (parent, name) 幂等入库并向量化。

用法：
    cd backend && uv run python scripts/ingest_textbooks.py [--source ../resources]

- 年级从「X年级」解析（一..九 → 1..9）；学科固定「数学」。
- 已存在且为 ready（且版本戳一致）的资料跳过，不重复向量化；否则重新向量化。
- 走与 API 完全相同的 service 层（存储 / 解析 / 状态机 / embedding），不经过 HTTP。
"""

from __future__ import annotations

import argparse
import asyncio
import re
import sys
import time
import uuid
from pathlib import Path

# 让脚本从 backend/ 启动时能 import app
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlmodel import Session, select  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.db import engine  # noqa: E402
from app.db.models import (  # noqa: E402
    Material,
    MaterialChunk,  # noqa: E402
    User,
)
from app.db.models.material import (  # noqa: E402
    CHUNKER_VERSION,
    INDEX_STATE_READY,
)
from app.features.materials import indexing  # noqa: E402
from app.features.materials.service import (  # noqa: E402
    reextract_metadata,
    upload_material,
)

_CN2NUM = {c: i for i, c in enumerate("一二三四五六七八九", start=1)}
SUBJECT = "数学"


def parse_grade(name: str) -> int | None:
    m = re.search(r"([一二三四五六七八九])年级", name)
    return _CN2NUM[m.group(1)] if m else None


def get_parent_id(session: Session) -> uuid.UUID:
    # 优先用 annilq 这个家长账号；没有就取第一个 parent
    user = session.exec(select(User).where(User.username == "annilq")).first()
    if user is None:
        user = session.exec(select(User).where(User.role == "parent")).first()
    if user is None:
        raise SystemExit("数据库里没有家长账号，请先注册一个家长")
    return user.id


def find_existing(session: Session, *, parent_id: str, name: str) -> Material | None:
    return session.exec(
        select(Material).where(
            Material.parent_id == parent_id, Material.name == name  # type: ignore[union-attr]
        )
    ).first()


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=str(Path(__file__).resolve().parent.parent.parent / "resources"))
    ap.add_argument(
        "--extract",
        action="store_true",
        help="逐本调用 DeepSeek 提取知识点（默认跳过，避免批量 API 开销；"
        "需要知识点可在资料库页单本「重新提取」）",
    )
    args = ap.parse_args()
    source = Path(args.source)

    if not args.extract:
        # 批量入库不调用 LLM：显式 subject/grade 已写入，知识点由骨架兜底，
        # 不影响向量化与检索（检索只依赖 subject/grade/query）。
        import app.features.materials.service as svc

        async def _noop(*_a, **_k):  # type: ignore[no-untyped-def]
            return ("skipped_no_engine", "批量入库跳过 AI 提取")
        svc._extract_and_align = _noop  # type: ignore[assignment]
    pdfs = sorted(source.glob("*.pdf"))
    if not pdfs:
        raise SystemExit(f"在 {source} 下没有找到 PDF")

    with Session(engine) as session:
        parent_id = get_parent_id(session)
        print(f"家长账号 parent_id = {parent_id}")  # type: ignore[unreachable]
        print(f"EMBEDDING_PROVIDER = {settings.EMBEDDING_PROVIDER}  MODEL = {settings.EMBEDDING_MODEL}")
        print("=" * 70)

        ok = skipped = failed = 0
        for path in pdfs:
            name = path.name
            grade = parse_grade(name)
            if grade is None:
                print(f"[跳过] {name} —— 文件名解析不出年级")
                continue
            data = path.read_bytes()
            t0 = time.time()
            try:
                existing = find_existing(session, parent_id=parent_id, name=name)
                if (
                    existing
                    and existing.index_state == INDEX_STATE_READY
                    and existing.embed_model == settings.EMBEDDING_MODEL
                    and existing.chunker_ver == CHUNKER_VERSION
                ):
                    if args.extract:
                        # 已入库且就绪：批量模式下仍重提取知识点（不重向量化）。
                        # reextract_metadata 全量刷新 knowledge_points，并把新点进
                        # 「待审」目录；学科/年级只补空白，不会覆盖我们已写死的数学/年级。
                        try:
                            res = await reextract_metadata(
                                session, parent_id=parent_id, material_id=existing.id
                            )
                            kps = res.material.knowledge_points or []
                            print(
                                f"[重提取] {name}  g{grade}  kp={len(kps)}  "
                                f"({time.time()-t0:.1f}s)"
                            )
                            ok += 1
                        except Exception as e:  # noqa: BLE001
                            print(
                                f"[提取异常] {name}  —— {type(e).__name__}: {e}"
                            )
                            failed += 1
                    else:
                        print(f"[已就绪·跳过] {name}  g{grade}  ({time.time()-t0:.1f}s)")
                        skipped += 1
                    continue

                mat = await upload_material(
                    session,
                    parent_id=parent_id,
                    filename=name,
                    data=data,
                    folder_id=None,
                    subject=SUBJECT,
                    grade=grade,
                )
                material = await indexing.vectorize_material(
                    session, parent_id=parent_id, material_id=mat.material.id
                )
                state = material.index_state
                if state == INDEX_STATE_READY:
                    cnt = len(
                        session.exec(
                            select(MaterialChunk.id).where(
                                MaterialChunk.material_id == material.id
                            )
                        ).all()
                    )
                    print(
                        f"[成功] {name}  g{grade}  state={state}  chunks={cnt}  "
                        f"({time.time()-t0:.1f}s)"
                    )
                    ok += 1
                else:
                    print(
                        f"[失败] {name}  g{grade}  state={state}  err={material.index_error}"
                    )
                    failed += 1
            except Exception as e:  # noqa: BLE001
                print(f"[异常] {name}  —— {type(e).__name__}: {e}")
                failed += 1

        print("=" * 70)
        print(f"成功 {ok} · 跳过 {skipped} · 失败 {failed} · 共 {len(pdfs)} 个 PDF")


if __name__ == "__main__":
    asyncio.run(main())
