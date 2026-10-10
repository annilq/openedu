"""图库兜底场景（ADR-0061 §U / ADR-0083）单元测试。

背景：教师**没配**知识点模板时，交互讲解此前一律返回 None —— 于是「正方形有
几条对称轴」这类最典型的题在题库详情 / 错题本里**永远不出图**，教师看到的就是
「功能没做」。几何的权威来源是图库（``figure_library`` 表），题面点名了图形就该
出图。

本文件钉住四件事：
1. 命中图形 → 出图，顶点直接来自图库 DB（与内置种子逐点一致）；
2. 没命中图形 → **None**（绝不臆造一个图形给纯计算题）；
3. 产出的是**纯几何** SceneSpec（``{kind, points, edges}``），旧字段一概不出；
4. 教师配了模板 → 用模板（图库只补几何，不改教师意图）。

DB 交互用真实的 ``db`` fixture（``init_db`` 已把 11 个内置图形 seed 进
``figure_library``）；无模板场景用**随机 teacher_id** 保证查不到任何知识点。
"""
import uuid

from app.db.models import KnowledgePoint
from app.features.materials.scene_figures import FIGURES
from app.features.materials.scene_fusion import (
    build_scene_spec_for_question,
    default_scene_from_figure,
    scene_spec_for_read,
)

_SUBJECT = "数学"
_GRADE = 4
_KP_NAME = "图形的运动（轴对称）"


def _square_points() -> list[list[float]]:
    square = next(f for f in FIGURES if f.key == "square")
    return [[x, y] for x, y in square.vertices]


def _square_edges() -> list[list[int]]:
    n = len(_square_points())
    return [[i, (i + 1) % n] for i in range(n)]


def test_default_scene_unknown_key_returns_none(db):
    assert default_scene_from_figure(db, None) is None
    assert default_scene_from_figure(db, "不存在的图形") is None


def test_default_scene_square_geometry_from_db(db):
    """正方形顶点必须**逐点等于**图库（种子）里的那份（几何单一事实源）。"""
    spec = default_scene_from_figure(db, "square")
    assert spec is not None
    assert spec["kind"] == "reflection"
    assert spec["points"] == _square_points()
    assert spec["edges"] == _square_edges()
    # 4 个顶点、轴对齐（零微扰）
    pts = spec["points"]
    assert len(pts) == 4
    assert sorted({p[0] for p in pts}) == [0.28, 0.72]
    assert sorted({p[1] for p in pts}) == [0.28, 0.72]


def test_default_scene_is_pure_geometry(db):
    """产出只剩 kind / points / edges（+derivedFrom）——旧字段不再出现。"""
    spec = default_scene_from_figure(db, "square")
    assert set(spec) == {"kind", "points", "edges", "derivedFrom"}
    for banned in ("inputs", "controls", "narrative", "outputs", "title", "editable"):
        assert banned not in spec


def test_build_falls_back_to_library_without_template(db):
    """无模板 + 题面点名正方形 → 照样出图（这是本次修复的核心）。"""
    spec = build_scene_spec_for_question(
        db,
        teacher_id=uuid.uuid4(),
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point=_KP_NAME,
        semester="",
        stem="正方形有几条对称轴？",
    )
    assert spec is not None
    assert spec["points"] == _square_points()
    assert spec["derivedFrom"] == "figure_library"


def test_option_group_attaches_per_option_geometry(db):
    """选项组里每个选项带自己的几何（前端逐个亲手试）。"""
    spec = build_scene_spec_for_question(
        db,
        teacher_id=uuid.uuid4(),
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point=_KP_NAME,
        stem="下面哪个图形是轴对称图形？",
        options=["A. 平行四边形", "B. 房子", "C. 风筝", "D. 箭头"],
    )
    assert spec is not None
    assert len(spec["optionGroup"]["items"]) == 4
    for item in spec["optionGroup"]["items"]:
        assert len(item["points"]) >= 3
        assert len(item["edges"]) >= 3


def test_build_no_figure_word_returns_none(db):
    """纯计算题没有图形可讲 → None，绝不臆造图形。"""
    assert (
        build_scene_spec_for_question(
            db,
            teacher_id=uuid.uuid4(),
            subject=_SUBJECT,
            grade=_GRADE,
            knowledge_point="两位数加减法",
            semester="",
            stem="学校图书馆有故事书 86 本，借出 47 本，还剩多少本？",
        )
        is None
    )


def test_build_ignores_stem_angle(db):
    """ADR-0083 决策 6：对称轴初值归 kind 外壳 → 题面角度不再进 SceneSpec。"""
    spec = build_scene_spec_for_question(
        db,
        teacher_id=uuid.uuid4(),
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point=_KP_NAME,
        stem="正方形沿 45° 的线对折能重合吗？",
    )
    assert spec is not None
    assert "axisAngle" not in spec
    assert spec["points"] == _square_points()


def test_template_still_wins_over_library(db):
    """教师配了模板 → 用模板；题面命中图形只**覆盖几何**，不换成库兜底。"""
    teacher_id = uuid.uuid4()
    house = next(f for f in FIGURES if f.key == "house")
    kp = KnowledgePoint(
        id=uuid.uuid4(),
        teacher_id=teacher_id,
        subject=_SUBJECT,
        grade=_GRADE,
        semester="",
        name=_KP_NAME,
        scenes=[
            {
                "kind": "reflection",
                "points": [[x, y] for x, y in house.vertices],
                "edges": [[i, (i + 1) % len(house.vertices)] for i in range(len(house.vertices))],
            }
        ],
    )
    db.add(kp)
    db.commit()
    try:
        spec = build_scene_spec_for_question(
            db,
            teacher_id=teacher_id,
            subject=_SUBJECT,
            grade=_GRADE,
            knowledge_point=_KP_NAME,
            stem="正方形有几条对称轴？",
        )
        assert spec is not None
        # 题面命中正方形 → 几何被覆盖成正方形；但走的是教师模板，不是库兜底
        assert spec["points"] == _square_points()
        assert "derivedFrom" not in spec
    finally:
        db.delete(kp)
        db.commit()


def test_scene_spec_for_read_prefers_snapshot(db):
    """有快照就原样返回（模板后续改动不影响已生成的题），且**不查库**。"""
    snapshot = {
        "kind": "reflection",
        "points": [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]],
        "edges": [[0, 1], [1, 2], [2, 0]],
    }
    out = scene_spec_for_read(
        db,
        snapshot=snapshot,
        teacher_id="p",
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point="KP",
    )
    assert out is snapshot


def test_scene_spec_for_read_empty_snapshot_falls_back(db):
    """空快照（JSON null 归一化后的 None / {}）等同没有 → 走回退。"""
    teacher_id = uuid.uuid4()
    assert (
        scene_spec_for_read(
            db,
            snapshot=None,
            teacher_id=teacher_id,
            subject=_SUBJECT,
            grade=_GRADE,
            knowledge_point="两位数加减法",
            stem="86 - 47 = ?",
        )
        is None
    )
    out = scene_spec_for_read(
        db,
        snapshot={},
        teacher_id=teacher_id,
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point=_KP_NAME,
        stem="长方形有几条对称轴？",
    )
    assert out is not None
    rectangle = next(f for f in FIGURES if f.key == "rectangle")
    assert out["points"] == [[x, y] for x, y in rectangle.vertices]
