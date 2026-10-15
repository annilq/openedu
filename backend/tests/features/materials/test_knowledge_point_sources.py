"""知识点溯源片段选择（ADR-0093）：命中排序 + 限量 + 零命中兜底。

旧行为把命中资料的**全部** chunk 按 seq 平铺返回：同一本书里点任何知识点，
看到的都是整本书（实测 58-157 段），教师无法核对「这个点出自哪一段」。
本文件锁定新行为：

1. 规范化词匹配（NFKC 归一全角/半角 + 去空白）找出提及该名字的段；
2. 按命中次数降序、seq 升序取前 10 段（一本书里概念章节自然浮到最上）；
3. 一段都不命中才兜底返回全本，并由 ``matched=False`` 告诉前端「说清楚」；
4. 资料级门禁不变：只有知识清单里含该名字的资料才参与（``Material.knowledge_points``）。
"""

from __future__ import annotations

import uuid

import pytest
from sqlmodel import Session, select

from app.db.models import Material, MaterialChunk, Role, User
from app.features.materials.service import get_knowledge_point_sources


@pytest.fixture()
def teacher(db: Session):
    u = User(
        username=f"src_{uuid.uuid4().hex[:8]}",
        display_name="溯源教师",
        role=Role.TEACHER,
        hashed_password="x",
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    yield u
    db.execute(select(MaterialChunk).where(MaterialChunk.teacher_id == u.id))
    db.execute(select(Material).where(Material.teacher_id == u.id))
    db.commit()


def _material_with_chunks(
    db: Session,
    teacher: User,
    *,
    name: str,
    knowledge_points: list[str],
    chunks: list[str],
) -> Material:
    m = Material(
        teacher_id=teacher.id,
        name=name,
        storage_key=f"src/{uuid.uuid4().hex}",
        text="教材全文",
        subject="数学",
        grade=4,
        knowledge_points=knowledge_points,
    )
    db.add(m)
    db.commit()
    db.refresh(m)
    for seq, content in enumerate(chunks):
        db.add(
            MaterialChunk(
                teacher_id=teacher.id,
                material_id=m.id,
                seq=seq,
                content=content,
                subject="数学",
                grade=4,
            )
        )
    db.commit()
    return m


def test_matched_name_returns_top_chunks_not_whole_book(
    db: Session, teacher: User
) -> None:
    """命中时只回最相关的几段：按命中次数降序、seq 升序，不带无关段。"""
    chunks = [f"第{i}段：讲位置与顺序，与目标知识点无关。" for i in range(12)]
    chunks[3] = "加法交换律：两个数相加，交换加数位置，和不变。"
    chunks[7] = "例：用加法交换律验算 27+15=15+27，加法交换律真有用。"
    chunks[7] += "再说一遍加法交换律。"
    chunks[11] = "练习里出现了加法交换律的题目一道。"
    _material_with_chunks(
        db,
        teacher,
        name="四下.pdf",
        knowledge_points=["加法交换律"],
        chunks=chunks,
    )

    res = get_knowledge_point_sources(
        db, teacher_id=teacher.id, subject="数学", grade=4, name="加法交换律"
    )

    assert len(res.sources) == 1
    src = res.sources[0]
    assert src.matched is True
    assert src.total_chunks == 12
    # 命中 3 次的段排最前，随后 1 次的两段按 seq 升序；9 段无关段全部出局
    assert [c.seq for c in src.chunks] == [7, 3, 11]


def test_fullwidth_variant_counts_as_hit(db: Session, teacher: User) -> None:
    """半角名 vs 全角正文：NFKC 归一后算命中，否则「1~5的认识」永远查不到。"""
    _material_with_chunks(
        db,
        teacher,
        name="一上.pdf",
        knowledge_points=["1~5的认识"],
        chunks=["本段出现 1～5 的认识 标题（全角波浪号）", "无关段"],
    )

    res = get_knowledge_point_sources(
        db, teacher_id=teacher.id, subject="数学", grade=4, name="1~5的认识"
    )

    assert len(res.sources) == 1
    assert res.sources[0].matched is True
    assert [c.seq for c in res.sources[0].chunks] == [0]


def test_zero_hit_falls_back_to_whole_book_with_flag(
    db: Session, teacher: User
) -> None:
    """零命中不假装成功：全本照给（不回归），但 matched=False 让前端说真话。"""
    chunks = [f"第{i}段正文" for i in range(5)]
    _material_with_chunks(
        db,
        teacher,
        name="一上.pdf",
        knowledge_points=["5以内的加法"],
        chunks=chunks,
    )

    res = get_knowledge_point_sources(
        db, teacher_id=teacher.id, subject="数学", grade=4, name="5以内的加法"
    )

    src = res.sources[0]
    assert src.matched is False
    assert src.total_chunks == 5
    assert [c.seq for c in src.chunks] == [0, 1, 2, 3, 4]


def test_result_is_capped_at_ten(db: Session, teacher: User) -> None:
    """高频名（实测「比」命中 60/137 段）也只回 10 段，按密度排序。"""
    chunks = [f"第{i}段也提到比" for i in range(15)]
    chunks.append("比的密集章节：" + "比" * 6)
    _material_with_chunks(
        db,
        teacher,
        name="六上.pdf",
        knowledge_points=["比"],
        chunks=chunks,
    )

    res = get_knowledge_point_sources(
        db, teacher_id=teacher.id, subject="数学", grade=4, name="比"
    )

    src = res.sources[0]
    assert src.matched is True
    assert src.total_chunks == 16
    assert len(src.chunks) == 10
    assert src.chunks[0].seq == 15  # 密度最高的段第一


def test_only_materials_listing_the_name_participate(
    db: Session, teacher: User
) -> None:
    """资料级门禁：清单里没这个名字的资料，哪怕正文提到了也不返回。"""
    _material_with_chunks(
        db,
        teacher,
        name="A.pdf",
        knowledge_points=["加法交换律"],
        chunks=["加法交换律的定义段"],
    )
    _material_with_chunks(
        db,
        teacher,
        name="B.pdf",
        knowledge_points=["加法结合律"],
        chunks=["这段也写了加法交换律，但 B 的清单里没有它"],
    )

    res = get_knowledge_point_sources(
        db, teacher_id=teacher.id, subject="数学", grade=4, name="加法交换律"
    )

    assert [s.material_name for s in res.sources] == ["A.pdf"]
