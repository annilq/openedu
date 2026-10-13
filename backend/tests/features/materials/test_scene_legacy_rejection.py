"""旧形场景数据不再被容忍（ADR-0091 ticket 02：生产端不做双读）。

ADR-0083 之前 / 之初，``kp.scenes`` 模板与快照可以是**旧形**：几何塞在
``inputs[key=='points']``，或摊平在顶层 ``points``/``edges``，选项组叫
``optionGroup``。彼时后端的选择是「读取 / 融合时容忍老形、零回写」。

ADR-0091 把这条路**堵死**：几何唯一载体是 ``Figure``，代码只认新形
（``kind`` + 主 ``figure`` + 可选 ``options`` 图形数组），旧形经
:func:`normalize_scene_spec` 一律拒绝——存量数据由
``scripts/migrate_scene_specs.py`` 一次性迁移，不留适配分支。本文件钉住后端侧
的两条拒绝语义（ADR-0089 起后端**不再从题面/选项猜图形**，故旧形被拒后
无图库兜底、只有「回退到有效模板」或 ``None``）：

1. 旧形模板 → 融合拒绝（``None``）：没有可上提的新形几何、也无题面猜测；
2. 旧形快照 → 读取路径拒绝透传，回退实时解析（快照铁律仍在：拒绝发生在
   「要不要用它」的判定上，不改写任何已落库数据）。

DB 交互用真实的 ``db`` fixture（``init_db`` 已 seed 11 个内置图形）。
"""
import uuid

from app.db.models import KnowledgePoint
from app.features.materials.scene_figures import BUILTIN_FIGURE_SEED
from app.features.materials.scene_fusion import (
    build_scene_spec_for_question,
    scene_spec_for_read,
)

_SUBJECT = "数学"
_GRADE = 4
_KP_NAME = "图形的运动（轴对称）"

# 一个**自定义**三角形（刻意不是内置预设）：用来证明旧形几何不被当成结果透传。
_LEGACY_TRI = [[0.20, 0.80], [0.80, 0.80], [0.50, 0.30]]


def _square_points() -> list[list[float]]:
    square = next(f for f in BUILTIN_FIGURE_SEED if f.key == "square")
    return [[x, y] for x, y in square.vertices]


def _legacy_scene() -> dict:
    """旧形（ADR-0083 之前）的单条 scene：几何在 inputs[points]，另带已废字段。"""
    return {
        "kind": "reflection",
        "title": "自定义·轴对称",
        "inputs": [
            {"key": "axisAngle", "label": "对称轴角度", "value": 90},
            {"key": "axisX", "value": 0.5},
            {"key": "axisY", "value": 0.5},
            {"key": "figure", "value": ""},
            {"key": "points", "label": "顶点", "value": _LEGACY_TRI},
        ],
        "controls": {"play": True, "pause": True, "scrub": True, "speed": True},
        "narrative": "这是旧文案，不应再被读取。",
        "outputs": {"isAxisymmetric": True},
        "editable": True,
    }


def _make_kp(teacher_id, scenes: list[dict]) -> KnowledgePoint:
    return KnowledgePoint(
        id=uuid.uuid4(),
        teacher_id=teacher_id,
        subject=_SUBJECT,
        grade=_GRADE,
        semester="",
        name=_KP_NAME,
        scenes=scenes,
    )


def test_legacy_template_rejected_yields_none(db):
    """旧形模板 → 融合拒绝（None）；后端不再从题面猜图形，故无兜底出图。"""
    teacher_id = uuid.uuid4()
    kp = _make_kp(teacher_id, [_legacy_scene()])
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
        # 旧形被拒绝、又无题面猜测 → 没有场景（不双读、不兜底）
        assert spec is None
    finally:
        db.delete(kp)
        db.commit()


def test_legacy_template_without_figure_yields_none(db):
    """旧形模板 + 无题面 → None：旧几何不再被上提，没有几何可画就不画。"""
    teacher_id = uuid.uuid4()
    kp = _make_kp(teacher_id, [_legacy_scene()])
    db.add(kp)
    db.commit()
    try:
        spec = build_scene_spec_for_question(
            db,
            teacher_id=teacher_id,
            subject=_SUBJECT,
            grade=_GRADE,
            knowledge_point=_KP_NAME,
            semester="",
        )
        assert spec is None
    finally:
        db.delete(kp)
        db.commit()


def test_scene_spec_for_read_rejects_legacy_snapshot(db):
    """快照不可变 + 不做双读：旧形快照拒绝透传，回退到有效模板（而非旧形骨架）。"""
    teacher_id = uuid.uuid4()
    kp = _make_kp(
        teacher_id,
        [
            {
                "kind": "reflection",
                "figure": {
                    "key": "house",
                    "label": "房子",
                    "points": _square_points(),
                    "edges": [[0, 1], [1, 2], [2, 0]],
                },
            }
        ],
    )
    db.add(kp)
    db.commit()
    try:
        legacy_snapshot = {
            "kind": "reflection",
            "inputs": [{"key": "points", "value": _LEGACY_TRI}],
            "narrative": "旧文案",
            "editable": True,
        }
        out = scene_spec_for_read(
            db,
            snapshot=legacy_snapshot,
            teacher_id=teacher_id,
            subject=_SUBJECT,
            grade=_GRADE,
            knowledge_point=_KP_NAME,
        )
        # 旧快照原样不被返回；回退实时解析 → 用教师配置的有效模板
        assert out is not None
        assert out.figure.key == "house"
        dumped = out.model_dump()
        assert "inputs" not in dumped and "points" not in dumped
    finally:
        db.delete(kp)
        db.commit()
