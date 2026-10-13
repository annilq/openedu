"""场景快照 / 模板融合（ADR-0061 §U / ADR-0083 / ADR-0091）单元测试。

背景（ADR-0089 起）：**后端不再从题面/选项文字猜图形**。一道题的主图形只来自两条
显式来源——教师给知识点配的模板（``kp.scenes``），或 AI 出题时显式引用的图形身份键
（经 ``figure_stamp`` 盖章）。「正方形有几条对称轴」这类题出图，靠的是教师把该知识点
配了 reflection 模板，而不是正则命中「正方形」三个字。

本文件钉住四件事：
1. 盖章原语 ``scene_spec_from_figure``：身份键 → 出图，顶点直接来自图库 DB（与种子逐点一致）；
2. 没配模板 / 无显式键 → **None**（绝不臆造一个图形给纯计算题）；
3. 产出的是**新形** SceneSpec（``kind`` + 主 ``figure``，ADR-0091：几何收进 Figure，
   无 derivedFrom / optionGroup 等旧字段）；
4. 教师配了模板 → 读路径用模板（curated/options 不丢，不做旧形双读）。

DB 交互用真实的 ``db`` fixture（``init_db`` 已把 11 个内置图形 seed 进 ``figure_library``）；
无模板场景用**随机 teacher_id** 保证查不到任何知识点。
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


def test_build_without_template_returns_none(db):
    """ADR-0089：无知识点模板（也无 AI 显式键）→ 返回 None，绝不臆造图形。

    旧行为靠正则命中题面「正方形」三字走图库兜底；新设计改为教师显式配模板 /
    AI 显式引用键，任何岔子都返回 None 而非猜。
    """
    spec = build_scene_spec_for_question(
        db,
        teacher_id=uuid.uuid4(),
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point=_KP_NAME,
        semester="",
    )
    assert spec is None


def test_build_template_figure_no_option_group(db):
    """ADR-0091 ticket 02：教师配了模板 → 用模板主图形；选项不再扫文字反猜。"""
    teacher_id = uuid.uuid4()
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
                    "key": "house",
                    "label": "房子",
                    "points": _square_points(),
                    "edges": _square_edges(),
                },
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
        )
        assert spec is not None
        assert spec.figure.key == "house"
        assert spec.options is None
    finally:
        db.delete(kp)
        db.commit()


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
        )
        is None
    )


def test_build_ignores_stem_angle(db):
    """ADR-0083 决策 6：对称轴初值归 kind 外壳 → 题面角度不再进 SceneSpec。"""
    teacher_id = uuid.uuid4()
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
                    "key": "house",
                    "label": "房子",
                    "points": _square_points(),
                    "edges": _square_edges(),
                },
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
        )
        assert spec is not None
        dumped = spec.model_dump()
        assert "axisAngle" not in dumped
        assert spec.figure.key == "house"
    finally:
        db.delete(kp)
        db.commit()


def test_template_still_wins(db):
    """教师配了模板 → 用模板（含 options/curated）；题面不再替换主图形。

    观察点：curated / options 只有走模板才带得出来——这是读路径区分「用模板」
    与「AI 显式键盖章」的唯一可见痕迹。
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
        )
        assert spec is not None
        # 主图形来自模板（不再被题面命中替换）
        assert spec.figure.key == house.key
        assert spec.figure.points == [[x, y] for x, y in house.vertices]
        # 模板的编排语境原样保留
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
    """ADR-0091 不做双读：旧形快照拒绝返回，回退模板解析（而非原样透传）。"""
    teacher_id = uuid.uuid4()
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
                    "key": "house",
                    "label": "房子",
                    "points": _square_points(),
                    "edges": _square_edges(),
                },
            }
        ],
    )
    db.add(kp)
    db.commit()
    try:
        legacy_snapshot = {
            "kind": "reflection",
            "points": [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]],
            "edges": [[0, 1], [1, 2], [2, 0]],
        }
        out = scene_spec_for_read(
            db,
            snapshot=legacy_snapshot,
            teacher_id=teacher_id,
            subject=_SUBJECT,
            grade=_GRADE,
            knowledge_point=_KP_NAME,
        )
        # 旧快照不被透传；回退模板解析 → 用教师模板
        assert out is not None
        assert out.figure.key == "house"
        assert "points" not in out.model_dump()
    finally:
        db.delete(kp)
        db.commit()


def test_scene_spec_for_read_empty_snapshot_falls_back(db):
    """空快照（JSON null 归一化后的 None / {}）等同没有 → 走回退模板解析。"""
    teacher_id = uuid.uuid4()
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
                    "key": "house",
                    "label": "房子",
                    "points": _square_points(),
                    "edges": _square_edges(),
                },
            }
        ],
    )
    db.add(kp)
    db.commit()
    try:
        # 无匹配知识点（无模板）→ None
        assert (
            scene_spec_for_read(
                db,
                snapshot=None,
                teacher_id=teacher_id,
                subject=_SUBJECT,
                grade=_GRADE,
                knowledge_point="两位数加减法",
            )
            is None
        )
        # 空快照回退到模板
        out = scene_spec_for_read(
            db,
            snapshot={},
            teacher_id=teacher_id,
            subject=_SUBJECT,
            grade=_GRADE,
            knowledge_point=_KP_NAME,
        )
        assert out is not None
        assert out.figure.key == "house"
    finally:
        db.delete(kp)
        db.commit()
