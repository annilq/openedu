"""向量化状态机（ADR-0055 §5）：手动触发 + 版本戳 + stale 失效。

状态迁移（只由本模块写）：
    pending --vectorize(成功)--> ready
    pending/ready/stale --vectorize(失败)--> failed
    ready --换模型/换切分器--> stale（``mark_stale_if_model_changed``，列表/检索前惰性触发）
    failed/stale --vectorize(重试)--> ready
"""

from __future__ import annotations

import struct
import uuid
from datetime import UTC, datetime

from sqlmodel import Session, select

from app.core.config import settings
from app.core.errors import AppErrorException, ErrCode
from app.db.models import CHUNKER_VERSION, Material, MaterialChunk
from app.db.models.material import (
    INDEX_STATE_FAILED,
    INDEX_STATE_READY,
    INDEX_STATE_STALE,
)
from app.features.materials import repository as repo
from app.features.materials.chunker import chunk_text
from app.features.materials.embedder import (
    EmbeddingUnavailableError,
    embed_texts,
)


def encode_vector(vec: list[float]) -> bytes:
    """float32 小端打包（1024 维 × 4B = 4KB/片，数千片量级毫无压力）。"""
    return struct.pack(f"<{len(vec)}f", *vec)


def decode_vector(blob: bytes) -> list[float]:
    n = len(blob) // 4
    return list(struct.unpack(f"<{n}f", blob[: n * 4]))


async def vectorize_material(
    session: Session, *, parent_id: uuid.UUID, material_id: uuid.UUID
) -> Material:
    """手动向量化 / 重新向量化。失败落 failed 态（附人话原因），不抛 500。"""
    material = repo.get_owned_material(
        session, parent_id=parent_id, material_id=material_id
    )

    def _fail(reason: str) -> Material:
        material.index_state = INDEX_STATE_FAILED
        material.index_error = reason
        session.add(material)
        session.commit()
        session.refresh(material)
        return material

    text = (material.text or "").strip()
    if not text:
        return _fail("资料没有可切分的文本")
    if not material.subject or not material.grade:
        return _fail("缺少学科 / 年级元数据，请先完成元数据提取")
    if settings.EMBEDDING_PROVIDER == "none":
        raise AppErrorException(
            ErrCode.LLM_UNAVAILABLE,
            "服务端未配置 embedding 模型（EMBEDDING_PROVIDER=none），无法向量化",
        )

    pieces = chunk_text(text)
    if not pieces:
        return _fail("切分后没有得到有效片段")
    try:
        vectors = await embed_texts(pieces)
    except EmbeddingUnavailableError as e:
        return _fail(str(e))

    # 全量重建：重向量化必须清旧片（切分器可能已变，残留旧片会混入两个空间）
    old = session.exec(
        select(MaterialChunk).where(MaterialChunk.material_id == material.id)
    ).all()
    for chunk in old:
        session.delete(chunk)
    for seq, (content, vec) in enumerate(zip(pieces, vectors, strict=True)):
        session.add(
            MaterialChunk(
                parent_id=parent_id,
                material_id=material.id,
                seq=seq,
                content=content,
                embedding=encode_vector(vec),
                embed_model=settings.EMBEDDING_MODEL,
                chunker_ver=CHUNKER_VERSION,
                subject=material.subject,
                grade=material.grade,
            )
        )
    material.index_state = INDEX_STATE_READY
    material.embed_model = settings.EMBEDDING_MODEL
    material.chunker_ver = CHUNKER_VERSION
    material.index_error = None
    material.indexed_at = datetime.now(UTC)
    session.add(material)
    session.commit()
    session.refresh(material)
    return material


def mark_stale_if_model_changed(session: Session, *, parent_id: uuid.UUID) -> int:
    """把「模型或切分器已变」的就绪资料标记 stale。返回标记数。

    惰性触发（列表 / 检索前调用）：不做后台任务、不搞事件——单家长量级下
    一条 UPDATE 比一套失效广播便宜得多。
    """
    stale = 0
    materials = session.exec(
        select(Material).where(
            Material.parent_id == parent_id, Material.index_state == INDEX_STATE_READY
        )
    ).all()
    for material in materials:
        if (
            material.embed_model != settings.EMBEDDING_MODEL
            or material.chunker_ver != CHUNKER_VERSION
        ):
            material.index_state = INDEX_STATE_STALE
            material.index_error = (
                "embedding 模型或切分策略已变更，向量已过期，请重新向量化"
            )
            session.add(material)
            stale += 1
    if stale:
        session.commit()
    return stale
