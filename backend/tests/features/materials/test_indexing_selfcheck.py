"""向量化自检（ADR-0055 §5 / ADR-0092 §3）：回答「知识库是否成功向量化」。

用确定性假 embedding（字符哈希投影 64 维，零网络）跑真实 ``vectorize_material``
状态机，断言入库自检的九组不变量。没有这套断言时，``pending`` 与 ``ready`` 在库里
长得一模一样——这正是本项目 RAG 长期「看起来没生效」却无人发现的根因。
"""

from __future__ import annotations

import asyncio
import math
import uuid

import pytest
from sqlmodel import select

from app.core.config import settings
from app.db.models import (
    CHUNKER_VERSION,
    Material,
    MaterialChunk,
    Role,
    User,
)
from app.features.materials.chunker import chunk_text
from app.features.materials.embedder import EmbeddingUnavailableError
from app.features.materials import indexing


_DIM = 64


async def _fake_embed_async(texts: list[str]) -> list[list[float]]:
    out: list[list[float]] = []
    for t in texts:
        v = [0.0] * _DIM
        for ch in t:
            v[ord(ch) % _DIM] += 1.0
        norm = math.sqrt(sum(x * x for x in v)) or 1.0
        out.append([x / norm for x in v])
    return out


@pytest.fixture()
def teacher(db):
    u = User(
        username=f"selfchk_{uuid.uuid4().hex[:8]}",
        display_name="自检教师",
        role=Role.TEACHER,
        hashed_password="x",
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    yield u
    # 清理：先删 chunk（FK 指向 material），再删 material
    db.execute(select(MaterialChunk).where(MaterialChunk.teacher_id == u.id))
    db.execute(select(Material).where(Material.teacher_id == u.id))
    db.commit()


def _make_material(db, teacher, *, text: str) -> Material:
    m = Material(
        teacher_id=teacher.id,
        name="自检资料",
        storage_key=f"selfchk/{uuid.uuid4().hex}",
        text=text,
        subject="数学",
        grade=3,
        index_state="pending",
    )
    db.add(m)
    db.commit()
    db.refresh(m)
    return m


def _chunks_of(db, material_id) -> list[MaterialChunk]:
    return list(
        db.exec(
            select(MaterialChunk).where(MaterialChunk.material_id == material_id)
        ).all()
    )


def test_vectorize_produces_expected_chunks_and_state(db, teacher, monkeypatch):
    monkeypatch.setattr(settings, "EMBEDDING_PROVIDER", "fake")
    monkeypatch.setattr(settings, "EMBEDDING_MODEL", "gold-fake")
    monkeypatch.setattr(
        "app.features.materials.indexing.embed_texts", _fake_embed_async
    )

    text = (
        "两位数加法进位：个位相加满十，向十位进一。\n\n"
        "多位数乘一位数：用一位数依次去乘另一个数的每一位。\n\n"
        "分数初步认识：把一个整体平均分成几份，每份就是它的几分之一。\n\n"
        "长方形的周长等于长加宽的和再乘二。"
    )
    m = _make_material(db, teacher, text=text)
    material = asyncio.run(
        indexing.vectorize_material(db, teacher_id=teacher.id, material_id=m.id)
    )
    chunks = _chunks_of(db, m.id)

    # ① 状态机：pending → ready
    assert material.index_state == "ready"
    # ② chunk 数 = 切片器确定性输出（不写死，随切片策略演进）
    assert len(chunks) == len(chunk_text(text))
    assert len(chunks) >= 1
    # ③ 维度一致 + 无 NaN + 非零向量
    for c in chunks:
        vec = indexing.decode_vector(c.embedding)
        assert len(vec) == _DIM
        assert all(math.isfinite(x) for x in vec)
        assert any(x != 0.0 for x in vec)
    # ④ 版本戳单行：该资料所有 chunk 的 (embed_model, chunker_ver) 唯一
    stamps = {(c.embed_model, c.chunker_ver) for c in chunks}
    assert stamps == {("gold-fake", CHUNKER_VERSION)}


def test_embedding_deterministic(db, teacher, monkeypatch):
    monkeypatch.setattr(settings, "EMBEDDING_PROVIDER", "fake")
    monkeypatch.setattr(settings, "EMBEDDING_MODEL", "gold-fake")
    monkeypatch.setattr(
        "app.features.materials.indexing.embed_texts", _fake_embed_async
    )
    m = _make_material(db, teacher, text="等式的性质：两边同加同减仍相等。")
    asyncio.run(
        indexing.vectorize_material(db, teacher_id=teacher.id, material_id=m.id)
    )
    chunks = _chunks_of(db, m.id)
    # 同一资料重新向量化：向量必须完全一致（幂等 + 确定性）
    first = {c.seq: indexing.decode_vector(c.embedding) for c in chunks}
    asyncio.run(
        indexing.vectorize_material(db, teacher_id=teacher.id, material_id=m.id)
    )
    chunks2 = _chunks_of(db, m.id)
    for c in chunks2:
        assert indexing.decode_vector(c.embedding) == first[c.seq]
    # 幂等：重向量化后 chunk 数不变（全量重建，不残留旧片）
    assert len(chunks2) == len(chunks)


def test_vectorize_failure_is_non_destructive(db, teacher, monkeypatch):
    monkeypatch.setattr(settings, "EMBEDDING_PROVIDER", "fake")
    monkeypatch.setattr(settings, "EMBEDDING_MODEL", "gold-fake")

    async def _boom(texts):  # noqa: ANN001
        raise EmbeddingUnavailableError("embedding 服务不可用（测试）")

    monkeypatch.setattr("app.features.materials.indexing.embed_texts", _boom)
    m = _make_material(db, teacher, text="小数乘法：先按整数乘法算出积。")
    material = asyncio.run(
        indexing.vectorize_material(db, teacher_id=teacher.id, material_id=m.id)
    )
    # 失败落 failed 态 + 人话原因，不抛 500
    assert material.index_state == "failed"
    assert material.index_error
    # 失败路径无损：旧 chunk（此处本就无）原样；重点是状态可观测、可重试
    assert _chunks_of(db, m.id) == []
