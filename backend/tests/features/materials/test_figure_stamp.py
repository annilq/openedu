"""图形目录投影 / 校验 / 盖章（ADR-0089 决策 3，ticket 01）。

钉住 `figure_stamp` 只装的三件事，以及它的三条纪律：

1. **目录投影**：``kp.scenes`` curated 图形优先 → 回落 ``figure_library`` 全量；
   教师自绘图形（``is_builtin=False``）与自编知识点都在目录里。
2. **校验**：``figure_key`` 必须落在目录内。
3. **盖章**：合法 key → 从图库（唯一权威）取几何内联，顺序 == 传入顺序；
   **全-or-无**——部分有图即整组丢弃；未知键 / 图库无行 → 丢弃且不抛错。

类型层面保证「顶点进不了提示词」：目录条目是 :class:`FigureRef`（只有 key + label），
断言它**没有** ``points`` / ``edges`` 字段。

DB 交互用真实 ``db`` fixture（``init_db`` 已 seed 11 个内置图形）。
"""
import uuid

from app.db.models import FigureLibrary, KnowledgePoint
from app.domain.figures import Figure
from app.features.materials.figure_stamp import (
    FigureRef,
    available_figures,
    render_figure_catalog,
    stamp_figures,
    stamp_scene_spec,
)

_SUBJECT = "数学"
_GRADE = 4
_KP_NAME = "图形的运动（轴对称）"

# 教师自绘三角形（刻意不是内置预设）——证明「自绘图形能进目录」。
_USER_POINTS = [[0.20, 0.80], [0.80, 0.80], [0.50, 0.30]]
_USER_EDGES = [[0, 1], [1, 2], [2, 0]]


def _square_figure() -> Figure:
    """一个合法的正方图形对象（key 在目录内，几何从库取，points 只是身份占位）。"""
    return Figure(key="square", label="正方形", points=[[0.0, 0.0]], edges=[[0, 0]])


def _para_figure() -> Figure:
    return Figure(key="para", label="平行四边形", points=[[0.0, 0.0]], edges=[[0, 0]])


def _scene_with_figure(key: str, label: str) -> dict:
    """新形 scene（ADR-0091）：kind + 主 figure（几何内联）。"""
    pts = [list(p) for p in _USER_POINTS]
    edges = [list(e) for e in _USER_EDGES]
    return {
        "kind": "reflection",
        "figure": {"key": key, "label": label, "points": pts, "edges": edges},
    }


def _add_user_figure(db, key: str, label: str) -> None:
    db.add(
        FigureLibrary(
            key=key,
            label=label,
            points=[list(p) for p in _USER_POINTS],
            edges=[list(e) for e in _USER_EDGES],
            is_builtin=False,
        )
    )
    db.commit()


# ───────────────────── 目录投影 ─────────────────────


def test_figure_ref_has_no_geometry_fields():
    """目录条目类型层面保证顶点进不了提示词：FigureRef 没有 points / edges。"""
    fields = set(FigureRef.model_fields)
    assert fields == {"key", "label"}
    assert "points" not in fields and "edges" not in fields


def test_available_figures_falls_back_to_library_when_no_scenes(db):
    """无知识点 / 无模板 → 回落图库全量，目录非空（部署后恒真）。"""
    refs = available_figures(db, kp=None)
    assert refs, "图库有内置种子时目录不应为空"
    keys = {r.key for r in refs}
    assert "square" in keys and "para" in keys
    assert all(isinstance(r, FigureRef) for r in refs)


def test_available_figures_includes_teacher_drawn_figure(db):
    """教师自绘图形（is_builtin=False）也进目录——本次的能力增量。"""
    key = f"user_{uuid.uuid4().hex[:8]}"
    _add_user_figure(db, key, "自绘三角形")
    try:
        refs = available_figures(db, kp=None)
        hit = [r for r in refs if r.key == key]
        assert len(hit) == 1 and hit[0].label == "自绘三角形"
    finally:
        db.delete(db.get(FigureLibrary, key))
        db.commit()


def test_available_figures_prefers_curated_from_kp_scenes(db):
    """知识点配了图形 → curated 优先（只给配的那批），不回落全量。"""
    key = f"user_{uuid.uuid4().hex[:8]}"
    _add_user_figure(db, key, "自绘三角形")
    teacher_id = uuid.uuid4()
    kp = KnowledgePoint(
        id=uuid.uuid4(),
        teacher_id=teacher_id,
        subject=_SUBJECT,
        grade=_GRADE,
        semester="",
        name=_KP_NAME,
        scenes=[_scene_with_figure(key, "自绘三角形")],
    )
    db.add(kp)
    db.commit()
    try:
        refs = available_figures(db, kp=kp)
        assert [(r.key, r.label) for r in refs] == [(key, "自绘三角形")]
        # curated 生效时不混入全量（否则模型的候选集会被无关图形淹没）。
        assert len(refs) < len(available_figures(db, kp=None))
    finally:
        db.delete(kp)
        db.delete(db.get(FigureLibrary, key))
        db.commit()


def test_available_figures_ignores_legacy_scene(db):
    """旧形模板跳过（不做双读），不因此让整份目录为空。"""
    kp = KnowledgePoint(
        id=uuid.uuid4(),
        teacher_id=uuid.uuid4(),
        subject=_SUBJECT,
        grade=_GRADE,
        semester="",
        name=_KP_NAME,
        scenes=[{"kind": "reflection", "points": _USER_POINTS, "edges": _USER_EDGES}],
    )
    # 不落库：available_figures 只读 kp.scenes。
    refs = available_figures(db, kp=kp)
    # 旧形被拒 → curated 为空 → 回落图库全量（非空）。
    assert refs and any(r.key == "square" for r in refs)


def test_render_catalog_only_key_and_label():
    """清单渲染只含 key + 中文名，绝不出现顶点数字。"""
    text = render_figure_catalog(
        [FigureRef(key="square", label="正方形"), FigureRef(key="para", label="平行四边形")]
    )
    assert text == "square — 正方形\npara — 平行四边形"
    assert "0." not in text and "[" not in text


# ───────────────────── 盖章（全-or-无） ─────────────────────


def test_stamp_figures_all_valid_inlines_geometry_in_order(db):
    """合法 key → 几何内联、顺序 == 传入顺序。"""
    allowed = {"square", "para"}
    out = stamp_figures(db, [_square_figure(), _para_figure()], allowed=allowed)
    assert out is not None
    assert [f.key for f in out] == ["square", "para"]
    # 顶点来自图库（非传入的占位几何）。
    assert len(out[0].points) == 4 and out[0].points != _square_figure().points


def test_stamp_figures_partial_none_returns_none(db):
    """全-or-无：一条有图、一条无图 → 整组丢弃。"""
    allowed = {"square", "para"}
    assert stamp_figures(db, [_square_figure(), None], allowed=allowed) is None


def test_stamp_figures_all_none_returns_none(db):
    assert stamp_figures(db, [None, None], allowed={"square"}) is None


def test_stamp_figures_unknown_key_returns_none(db):
    """未知身份键（模型幻觉）→ 丢弃，不抛错。"""
    ghost = Figure(key="不存在", label="x", points=[[0.0, 0.0]], edges=[[0, 0]])
    assert stamp_figures(db, [ghost], allowed={"不存在"}) is None


def test_stamp_figures_key_outside_catalog_returns_none(db):
    """key 在库里有，但不在本次目录内 → 丢弃（校验 key ∈ 目录）。"""
    assert stamp_figures(db, [_square_figure()], allowed={"para"}) is None


def test_stamp_figures_empty_returns_none(db):
    assert stamp_figures(db, [], allowed={"square"}) is None


# ───────────────────── 答疑侧盖章 ─────────────────────


def test_stamp_scene_spec_valid_key(db):
    spec = stamp_scene_spec(db, "square", allowed={"square"})
    assert spec is not None
    assert spec.kind == "reflection"
    assert spec.figure is not None and spec.figure.key == "square"


def test_stamp_scene_spec_rejects_missing_or_outside(db):
    assert stamp_scene_spec(db, None, allowed={"square"}) is None
    assert stamp_scene_spec(db, "", allowed={"square"}) is None
    assert stamp_scene_spec(db, "para", allowed={"square"}) is None
    # 在目录内但图库无此行（目录与图库不一致）→ 不发射。
    assert stamp_scene_spec(db, "不存在的图形", allowed={"不存在的图形"}) is None
