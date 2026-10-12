"""场景规格（SceneSpec）——一次演示的快照契约（ADR-0083 决策 5 / ADR-0091）。

``SceneSpec`` 从「把顶点摊平在自己身上」改为**持有** :class:`~app.domain.figures.Figure`：
一次演示 = ``kind`` 外壳 + 一个主图形 +（可选）一组选项图形。交互参数（轴初值 /
控件 / 引导语）**不进** spec——它们归 kind 外壳，几何与交互不互相污染。

:func:`normalize_scene_spec` 是读取路径的**唯一校验入口**：新形 → ``SceneSpec``，
旧形 / 非法 → ``None``（上层走空态，不臆造几何）。

统一后**不做双读**：旧形一律拒绝，不留适配分支——双读正是「两套形状」的持久化，
留着就白统一了。拒绝时返回**空**而不是兜一个图形出来：渲染期的最后兜底图形
只在画布上兜底，**不参与落库**（ADR-0091 §5）。
"""

from __future__ import annotations

from typing import Any

from sqlmodel import SQLModel

from app.domain.figures import Figure

__all__ = ["SceneSpec", "normalize_scene_spec"]

# 旧形的键：出现任意一个即判为旧形（顶点摊平在顶层 / 旧选项组 / 来源标记）。
# 显式拒绝而非忽略——忽略就是「旧形照样能过」，双读换个名字又回来了。
_LEGACY_KEYS = frozenset({"points", "edges", "optionGroup", "derivedFrom", "inputs"})


class SceneSpec(SQLModel):
    """一次演示的快照：**kind 外壳 + 图形**（几何部分收进 ``Figure``）。

    - ``kind``：稳定契约，决定前端用哪套交互外壳。
    - ``figure``：主图形（演示对象）。
    - ``options``：选项组（原 ``optionGroup.items``），非空时前端走图形画廊。
    - ``curated``：课件编排语境（原 ``optionGroup.curated``）。

    ``figure`` 与 ``options`` **至少有一个**：都没有就没有几何可画，校验入口直接拒绝。
    """

    kind: str
    figure: Figure | None = None
    options: list[Figure] | None = None
    curated: bool = False


def normalize_scene_spec(raw: Any) -> SceneSpec | None:
    """读路径唯一校验入口：新形 dict → ``SceneSpec``；旧形 / 非法 → ``None``。

    三态：
    - **新形直读**：``{kind, figure?, options?, curated?}`` 原样返回（顶点在图形里）。
    - **旧形拒绝**：顶层摊平的 ``points`` / ``edges``、``optionGroup``、
      ``derivedFrom``、``inputs`` → ``None``，不静默包成 ``figure``。
    - **残缺拒绝**：缺 ``kind``、图形缺身份键、顶点或连接关系为空 / 畸形 → ``None``。

    选项是**全-or-无**：任一条目不合规则整份 spec 拒绝，不留半份几何。
    """
    if not isinstance(raw, dict) or not raw:
        return None
    if _LEGACY_KEYS.intersection(raw):
        return None
    kind = raw.get("kind")
    if not isinstance(kind, str) or not kind.strip():
        return None

    raw_figure = raw.get("figure")
    figure = _figure_from(raw_figure)
    if raw_figure is not None and figure is None:
        # 给了主图形却不合规 → 拒绝，而不是降级成「无图形」。
        return None

    raw_options = raw.get("options")
    options: list[Figure] | None = None
    if raw_options is not None:
        if not isinstance(raw_options, list):
            return None
        options = []
        for item in raw_options:
            option = _figure_from(item)
            if option is None:
                return None
            options.append(option)

    if figure is None and not options:
        return None

    curated = raw.get("curated", False)
    if not isinstance(curated, bool):
        return None
    return SceneSpec(kind=kind, figure=figure, options=options or None, curated=curated)


def _figure_from(raw: Any) -> Figure | None:
    """图形 dict → ``Figure``；缺身份键 / 空几何 / 几何畸形 → ``None``。"""
    if not isinstance(raw, dict):
        return None
    key = raw.get("key")
    if not isinstance(key, str) or not key.strip():
        return None
    points = _points_from(raw.get("points"))
    if not points:
        return None
    edges = _edges_from(raw.get("edges"), len(points))
    if not edges:
        return None
    label = raw.get("label")
    return Figure(
        key=key,
        label=label if isinstance(label, str) else None,
        points=points,
        edges=edges,
    )


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _is_index(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _points_from(raw: Any) -> list[list[float]]:
    """顶点：``[[x, y], ...]``。任一元素不是「两个数」→ 整份几何作废（不截取、不补点）。"""
    if not isinstance(raw, list) or not raw:
        return []
    points: list[list[float]] = []
    for item in raw:
        if not isinstance(item, (list, tuple)) or len(item) != 2:
            return []
        if not all(_is_number(v) for v in item):
            return []
        points.append([float(item[0]), float(item[1])])
    return points


def _edges_from(raw: Any, n_points: int) -> list[list[int]]:
    """连接关系：``[[i, j], ...]``。非整数索引或越界 → 整份几何作废。"""
    if not isinstance(raw, list) or not raw:
        return []
    edges: list[list[int]] = []
    for item in raw:
        if not isinstance(item, (list, tuple)) or len(item) != 2:
            return []
        i, j = item
        if not _is_index(i) or not _is_index(j):
            return []
        if not 0 <= i < n_points or not 0 <= j < n_points:
            return []
        edges.append([i, j])
    return edges
