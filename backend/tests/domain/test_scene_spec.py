"""``normalize_scene_spec`` 单测（ADR-0091 ticket 01）。

校验入口的三态：**合法新形直读 / 旧形（顶点摊平在顶层）拒绝 / 身份键缺失拒绝**。
拒绝一律返回 ``None``——不静默适配成旧形，也不兜出任何图形（渲染期的最后兜底
图形**不参与落库**）。上层据此走空态，不臆造几何。

本票是 expand 步骤：校验入口尚未接任何生产 / 消费路径，故这里全是纯函数断言。
"""

import pytest

from app.domain.scene_spec import SceneSpec, normalize_scene_spec

_PARA = {
    "key": "para",
    "label": "平行四边形",
    "points": [[0.30, 0.40], [0.70, 0.40], [0.82, 0.70], [0.42, 0.70]],
    "edges": [[0, 1], [1, 2], [2, 3], [3, 0]],
}
_SQUARE = {
    "key": "square",
    "label": "正方形",
    "points": [[0.30, 0.30], [0.70, 0.30], [0.70, 0.70], [0.30, 0.70]],
    "edges": [[0, 1], [1, 2], [2, 3], [3, 0]],
}

# 渲染期的最后兜底图形（房子）——与前端 kFallbackFigure 同形
# （``frontend/lib/shared/domain/figures.dart:45``）。它只在画布上兜底，
# **不得被写成快照**：一旦进了校验入口的产出，它就会被落库，身份也就假了。
_FALLBACK_HOUSE_POINTS = [
    [0.30, 0.70],
    [0.70, 0.70],
    [0.70, 0.45],
    [0.50, 0.25],
    [0.30, 0.45],
]


def _figures(spec: SceneSpec | None) -> list:
    """规格里出现的全部图形（主图形 + 选项），用于「兜底不落库」的扫描。"""
    if spec is None:
        return []
    out = [] if spec.figure is None else [spec.figure]
    return out + list(spec.options or [])


# ── 新形直读 ─────────────────────────────────────────────────────────
def test_new_form_with_single_figure_reads_through():
    spec = normalize_scene_spec({"kind": "reflection", "figure": _PARA})
    assert spec is not None
    assert spec.kind == "reflection"
    assert spec.figure is not None
    assert spec.figure.key == "para"
    assert spec.figure.label == "平行四边形"
    assert spec.figure.points == _PARA["points"]
    assert spec.figure.edges == _PARA["edges"]
    assert spec.options is None
    assert spec.curated is False


def test_new_form_with_options_reads_through():
    spec = normalize_scene_spec(
        {
            "kind": "reflection",
            "figure": _PARA,
            "options": [_SQUARE],
            "curated": True,
        }
    )
    assert spec is not None
    assert [f.key for f in spec.options or []] == ["square"]
    assert spec.curated is True


def test_geometry_lives_only_inside_figure():
    """统一后的形状：顶点不出现在顶层，只在 figure / options 里。"""
    spec = normalize_scene_spec({"kind": "reflection", "figure": _PARA})
    assert spec is not None
    dumped = spec.model_dump()
    assert "points" not in dumped
    assert "edges" not in dumped


def test_normalize_is_idempotent():
    """幂等：校验过的规格再过一次校验入口结果不变（迁移重跑不会漂）。"""
    raw = {"kind": "reflection", "figure": _PARA, "options": [_SQUARE], "curated": True}
    once = normalize_scene_spec(raw)
    assert once is not None
    assert normalize_scene_spec(once.model_dump()) == once


# ── 旧形拒绝 ─────────────────────────────────────────────────────────
def test_legacy_top_level_geometry_is_rejected():
    """旧形：顶点摊平在顶层 → 拒绝，**不是**静默包成 figure。"""
    raw = {"kind": "reflection", "points": _PARA["points"], "edges": _PARA["edges"]}
    assert normalize_scene_spec(raw) is None


def test_legacy_option_group_is_rejected():
    """旧形的选项组（无身份键的条目）：连 spec 一起拒绝，不逐条降级。"""
    raw = {
        "kind": "reflection",
        "points": _PARA["points"],
        "edges": _PARA["edges"],
        "optionGroup": {
            "curated": True,
            "items": [{"label": "正方形", "caption": "正方形", **_SQUARE}],
        },
    }
    assert normalize_scene_spec(raw) is None


def test_legacy_derived_from_marker_is_rejected():
    """来源标记随旧形一起退场：带它的 spec 是旧形，一律拒绝。"""
    raw = {
        "kind": "reflection",
        "points": _PARA["points"],
        "edges": _PARA["edges"],
        "derivedFrom": "figure_library",
    }
    assert normalize_scene_spec(raw) is None


# ── 身份键 / 几何缺失拒绝 ────────────────────────────────────────────
@pytest.mark.parametrize(
    "figure",
    [
        {"label": "平行四边形", "points": _PARA["points"], "edges": _PARA["edges"]},
        {"key": "", "points": _PARA["points"], "edges": _PARA["edges"]},
        {"key": "   ", "points": _PARA["points"], "edges": _PARA["edges"]},
        {"key": None, "points": _PARA["points"], "edges": _PARA["edges"]},
    ],
    ids=["missing-key", "empty-key", "blank-key", "null-key"],
)
def test_figure_without_identity_key_is_rejected(figure):
    assert normalize_scene_spec({"kind": "reflection", "figure": figure}) is None


@pytest.mark.parametrize(
    "figure",
    [
        {"key": "para", "points": [], "edges": _PARA["edges"]},
        {"key": "para", "points": _PARA["points"], "edges": []},
        {"key": "para", "points": None, "edges": None},
    ],
    ids=["empty-points", "empty-edges", "null-geometry"],
)
def test_figure_without_geometry_is_rejected(figure):
    assert normalize_scene_spec({"kind": "reflection", "figure": figure}) is None


def test_malformed_points_or_edges_are_rejected():
    """顶点必须是数对、连接必须是顶点索引对——畸形几何不进渲染。"""
    assert normalize_scene_spec(
        {"kind": "reflection", "figure": {"key": "para", "points": [[0.3]], "edges": [[0, 0]]}}
    ) is None
    assert normalize_scene_spec(
        {
            "kind": "reflection",
            "figure": {"key": "para", "points": _PARA["points"], "edges": [[0, 9]]},
        }
    ) is None


def test_option_without_identity_key_rejects_whole_spec():
    """选项是全-or-无：一个条目不合规，整份 spec 拒绝（不留半份几何）。"""
    raw = {
        "kind": "reflection",
        "options": [_SQUARE, {"label": "圆形", "points": _PARA["points"], "edges": _PARA["edges"]}],
    }
    assert normalize_scene_spec(raw) is None


def test_spec_without_any_figure_is_rejected():
    """主图形与选项皆空 → 拒绝（上层走空态，不画空画布）。"""
    assert normalize_scene_spec({"kind": "reflection"}) is None
    assert normalize_scene_spec({"kind": "reflection", "figure": None}) is None
    assert normalize_scene_spec({"kind": "reflection", "options": []}) is None


@pytest.mark.parametrize(
    "raw",
    [None, {}, [], "reflection", 42, {"figure": _PARA}],
    ids=["none", "empty-dict", "list", "str", "int", "missing-kind"],
)
def test_non_spec_or_kindless_input_is_rejected(raw):
    assert normalize_scene_spec(raw) is None


def test_blank_kind_is_rejected():
    assert normalize_scene_spec({"kind": "", "figure": _PARA}) is None
    assert normalize_scene_spec({"kind": "  ", "figure": _PARA}) is None


# ── 兜底图形不参与落库 ───────────────────────────────────────────────
def test_render_fallback_figure_is_never_produced():
    """渲染期的最后兜底图形（房子）不得进快照。

    最容易被写成快照的正是「spec 里没有几何」这一类输入——旧实现会顺手兜一个形状。
    校验入口在任何输入下都不许产出它：几何缺失就是缺失，交给上层走空态。
    """
    geometry_less = [
        {"kind": "reflection"},
        {"kind": "reflection", "figure": None},
        {"kind": "reflection", "points": _PARA["points"], "edges": _PARA["edges"]},
        {"kind": "reflection", "figure": {"key": "para", "points": [], "edges": []}},
    ]
    produced = [f for raw in geometry_less for f in _figures(normalize_scene_spec(raw))]
    assert produced == []

    # 合法输入同样不会冒出兜底形状：归一化只搬运调用方给的几何。
    valid = [
        {"kind": "reflection", "figure": _PARA},
        {"kind": "reflection", "figure": _PARA, "options": [_SQUARE]},
    ]
    produced = [f for raw in valid for f in _figures(normalize_scene_spec(raw))]
    assert produced  # 正例确实产出了图形，上面的扫描不是空跑
    assert _FALLBACK_HOUSE_POINTS not in [f.points for f in produced]
