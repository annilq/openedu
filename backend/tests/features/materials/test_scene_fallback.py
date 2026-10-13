"""图库兜底场景（ADR-0061 §U / ADR-0083 / ADR-0091）单元测试。

背景：教师**没配**知识点模板时，交互讲解此前一律返回 None —— 于是「正方形有
几条对称轴」这类最典型的题在题库详情 / 错题本里**永远不出图**，教师看到的就是
「功能没做」。几何的权威来源是图库（``figure_library`` 表），题面点名了图形就该
出图。

本文件钉住四件事：
1. 命中图形 → 出图，顶点直接来自图库 DB（与内置种子逐点一致）；
2. 没命中图形 → **None**（绝不臆造一个图形给纯计算题）；
3. 产出的是**新形** SceneSpec（``kind`` + 主 ``figure``，ADR-0091：几何收进
   Figure，无 derivedFrom / optionGroup 等旧字段）；
4. 教师配了模板 → 用模板（题面图形只**替换主图形**，curated/options 不丢）。

DB 交互用真实的 ``db`` fixture（``init_db`` 已把 11 个内置图形 seed 进
``figure_library``）；无模板场景用**随机 teacher_id** 保证查不到任何知识点。
"""
import uuid

from app.db.models import KnowledgePoint
from app.domain.scene_spec import SceneSpec
from app.features.materials.scene_figures import BUILTIN_FIGURE_SEED
from app.features.materials.scene_fusion import (
    build_scene_spec_for_question,
    scene_spec_for_read,
    scene_spec_from_figure,
)

_SUBJECT = "数学"
_GRADE = 4
_KP_NAME = "图形的运动（轴对称）"


def _square_points() -> list[list[float]]:
    square = next(f for f in BUILTIN_FIGURE_SEED if f.key == "square")
    return [[x, y] for x, y in square.vertices]


def _square_edges() -> list[list[int]]:
    n = len(_square_points())
    return [[i, (i + 1) % n] for i in range(n)]


def test_stamp_unknown_key_returns_none(db):
    assert scene_spec_from_figure(db, None) is None
    assert scene_spec_from_figure(db, "不存在的图形") is None


def test_stamp_square_geometry_from_db(db):
    """正方形顶点必须**逐点等于**图库（种子）里的那份（几何单一事实源）。"""
    spec = scene_spec_from_figure(db, "square")
    assert isinstance(spec, SceneSpec)
    assert spec.kind == "reflection"
    assert spec.figure is not None
    assert spec.figure.key == "square"
    assert spec.figure.points == _square_points()
    assert spec.figure.edges == _square_edges()
    # 4 个顶点、轴对齐（零微扰）
    pts = spec.figure.points
    assert len(pts) == 4
    assert sorted({p[0] for p in pts}) == [0.28, 0.72]
    assert sorted({p[1] for p in pts}) == [0.28, 0.72]


def test_stamp_is_new_shape(db):
    """ADR-0091：产出是新形 SceneSpec——kind + 主 figure，旧字段一概不出。"""
    spec = scene_spec_from_figure(db, "square")
    dumped = spec.model_dump()
    assert set(dumped) == {"kind", "figure", "options", "curated"}
    for banned in ("points", "edges", "derivedFrom", "inputs", "controls", "narrative"):
        assert banned not in dumped
    assert dumped["figure"]["key"] == "square"


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
    assert spec.figure.key == "square"
    assert spec.figure.points == _square_points()
    # 来源标记字段已从生产端移除（ADR-0091）：图库兜底与模板替换同形
    assert "derivedFrom" not in spec.model_dump()


def test_build_attaches_no_option_group(db):
    """ADR-0091 ticket 02：兜底路径也不再挂 optionGroup（选项文字反猜已删）。"""
    spec = build_scene_spec_for_question(
        db,
        teacher_id=uuid.uuid4(),
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point=_KP_NAME,
        stem="正方形是轴对称图形吗？",
        options=["A. 平行四边形", "B. 房子", "C. 风筝", "D. 箭头"],
    )
    assert spec is not None
    assert spec.figure.key == "square"
    assert spec.options is None


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
    dumped = spec.model_dump()
    assert "axisAngle" not in dumped
    assert spec.figure.points == _square_points()


def test_template_still_wins_over_library(db):
    """教师配了模板 → 用模板；题面命中图形只**替换主图形**，编排语境不丢。

    观察点：curated / options 只有走模板才带得出来（图库兜底盖章不带）——
    derivedFrom 删除后，这是区分两条路径的唯一可见痕迹。
    """
    teacher_id = uuid.uuid4()
    house = next(f for f in BUILTIN_FIGURE_SEED if f.key == "house")
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
                "figure": {
                    "key": house.key,
                    "label": house.label,
                    "points": [[x, y] for x, y in house.vertices],
                    "edges": [
                        [i, (i + 1) % len(house.vertices)]
                        for i in range(len(house.vertices))
                    ],
                },
                "options": [
                    {
                        "key": "square",
                        "label": "正方形",
                        "points": _square_points(),
                        "edges": _square_edges(),
                    }
                ],
                "curated": True,
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
        # 题面命中正方形 → 主图形被替换成正方形；但走的是教师模板
        assert spec.figure.key == "square"
        assert spec.figure.points == _square_points()
        # 模板的编排语境原样保留（证明不是库兜底盖章）
        assert spec.curated is True
        assert spec.options is not None and spec.options[0].key == "square"
    finally:
        db.delete(kp)
        db.commit()


def test_scene_spec_for_read_prefers_snapshot(db):
    """有快照就校验后返回（模板后续改动不影响已生成的题），且**不查库**。"""
    snapshot = {
        "kind": "reflection",
        "figure": {
            "key": "user_abc123",
            "label": "自绘三角形",
            "points": [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]],
            "edges": [[0, 1], [1, 2], [2, 0]],
        },
    }
    out = scene_spec_for_read(
        db,
        snapshot=snapshot,
        teacher_id="p",
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point="KP",
    )
    assert out is not None
    assert out.figure.key == "user_abc123"
    assert out.figure.points == snapshot["figure"]["points"]
    # 产物是全新对象：改快照 dict 不影响已返回的 spec（快照铁律）
    snapshot["figure"]["points"][0][0] = 0.999
    assert out.figure.points[0][0] == 0.0


def test_scene_spec_for_read_rejects_legacy_snapshot(db):
    """ADR-0091 不做双读：旧形快照拒绝返回，回退实时解析（而非原样透传）。"""
    legacy_snapshot = {
        "kind": "reflection",
        "points": [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]],
        "edges": [[0, 1], [1, 2], [2, 0]],
    }
    out = scene_spec_for_read(
        db,
        snapshot=legacy_snapshot,
        teacher_id=uuid.uuid4(),
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point=_KP_NAME,
        stem="正方形有几条对称轴？",
    )
    # 旧快照不被透传；回退实时解析 → 图库盖章（正方形）
    assert out is not None
    assert out.figure.key == "square"
    assert "points" not in out.model_dump()


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
    rectangle = next(f for f in BUILTIN_FIGURE_SEED if f.key == "rectangle")
    assert out.figure.key == "rectangle"
    assert out.figure.points == [[x, y] for x, y in rectangle.vertices]
