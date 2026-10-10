"""旧形 ``kp.scenes`` 模板的向后兼容（ADR-0083 T03 迁移接缝）。

存量知识点的 ``scenes`` 是 ADR-0083 之前的**老形**：几何塞在
``inputs[key=='points']``，另带 ``controls``/``narrative``/``title``/``outputs``/
``editable``。本轮纪律是「**零回写** ``kp.scenes``」——不改写历史数据，只在读取 /
融合时容忍老形。本文件钉住后端侧的三条契约：

1. 老形模板 + 题面点名图形 → 融合后**顶层** ``points``/``edges`` 就位
   （新形渲染器 / 适配层直接可用），老形骨架仍在（不丢字段）。
2. 老形模板 + 题面**没有**图形 → 几何仍在 ``inputs[points]``（前端适配层可读），
   **不丢**——绝不当成「没配模板」而回退图库兜底。
3. 快照**不可变**：``scene_spec_for_read`` 有快照就原样返回，不因库 / 外壳改动而变。

DB 交互用真实的 ``db`` fixture（``init_db`` 已 seed 11 个内置图形）。
"""
import uuid

from app.db.models import KnowledgePoint
from app.features.materials.scene_figures import FIGURES
from app.features.materials.scene_fusion import (
    build_scene_spec_for_question,
    scene_spec_for_read,
)

_SUBJECT = "数学"
_GRADE = 4
_KP_NAME = "图形的运动（轴对称）"

# 一个**自定义**三角形（刻意不是内置预设）：用来证明老形模板的几何被原样带过来。
_LEGACY_TRI = [[0.20, 0.80], [0.80, 0.80], [0.50, 0.30]]


def _square_points() -> list[list[float]]:
    square = next(f for f in FIGURES if f.key == "square")
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


def _legacy_points_of(spec: dict) -> list | None:
    """从老形 spec 的 inputs 里取几何（模拟前端适配层要做的上提）。"""
    for inp in spec.get("inputs", []):
        if isinstance(inp, dict) and inp.get("key") == "points":
            return inp.get("value")
    return None


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


def test_legacy_template_with_figure_yields_top_level_geometry(db):
    """老形模板 + 题面点名正方形 → 顶层 points/edges 就位（新渲染器直接可读）。"""
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
            stem="正方形有几条对称轴？",
        )
        assert spec is not None
        # 题面命中正方形 → 顶层几何被覆盖成正方形（新形字段就位）
        assert spec["points"] == _square_points()
        assert len(spec["edges"]) == 4
        # 走的是教师模板（老形骨架原样保留），不是图库兜底
        assert "derivedFrom" not in spec
        assert "inputs" in spec
    finally:
        db.delete(kp)
        db.commit()


def test_legacy_template_without_figure_keeps_geometry(db):
    """老形模板 + 题面没有图形 → 几何仍在 inputs[points]，不丢、不回退兜底。"""
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
            # 纯文字题面：抽不出任何图形 key。
            stem="这条折线一共有几段？",
        )
        assert spec is not None
        # 老形几何仍在 → 前端适配层能上提，渲染不丢图
        assert _legacy_points_of(spec) == _LEGACY_TRI
        # 没有被图库兜底顶掉（否则 derivedFrom 会冒出来）
        assert "derivedFrom" not in spec
    finally:
        db.delete(kp)
        db.commit()


def test_scene_spec_for_read_returns_legacy_snapshot_as_is(db):
    """快照不可变：老形快照原样返回，不查库、不因库/外壳改动而变。"""
    legacy_snapshot = {
        "kind": "reflection",
        "inputs": [{"key": "points", "value": _LEGACY_TRI}],
        "narrative": "旧文案",
        "editable": True,
    }
    out = scene_spec_for_read(
        db,
        snapshot=legacy_snapshot,
        teacher_id="p",
        subject=_SUBJECT,
        grade=_GRADE,
        knowledge_point=_KP_NAME,
        stem="正方形有几条对称轴？",
    )
    assert out is legacy_snapshot
