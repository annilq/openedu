"""内置图形几何**种子**（ADR-0061 §O / ADR-0083）。

几何事实源已是 ``figure_library`` 表（ADR-0083 决策 1）：渲染 / 出题 / 课件一律查表
（:func:`figure_geometry`），代码里只剩一个职责——**新库首次安装时把这 11 个内置图形
灌进去**。因此：

- 本模块**不再下发任何东西**：`frontend/scripts/gen_figures.py` 与前端
  `figures.dart` 的 parity 锁已随 ADR-0083 退役（前端改为创作 UI 按需
  `GET /scene-library/figures`）。
- 种子**不带任何 axis 属性**（决策 2）：对称判定改为纯视觉（拖轴 + 翻转演示），
  图库不存 authored 轴值。用户交互的轴**初值**属 kind 交互外壳，见
  `scene_templates.REFLECTION_SHELL` 的 ``axisAngle`` ——「初值」不是关于图形的断言。
- ``note`` 是教学意图说明（「para 为什么必须歪着」），随种子写进 DB 的 ``note`` 列；
  它给维护者看，不进渲染载荷。

⚠️ 改顶点只改这里，并注意**种子只在「库里还没有这一行」时写**（幂等补齐，不覆盖
既有行）：改完已有库需要写迁移或先删行，否则改了不生效。

坐标归一化到 0..1、y 向下（与前端画布一致）。
"""
from __future__ import annotations

from typing import Any, NamedTuple

from sqlmodel import Session, select

from app.db.models import FigureLibrary


class SeedFigure(NamedTuple):
    """一个内置图形：归一化顶点 + 中文名 + 教学意图说明。**没有任何 axis 属性**。"""

    key: str
    label: str
    #: [(x, y), ...]，x/y ∈ 0..1，y 向下；按序连成多边形。
    vertices: list[tuple[float, float]]
    #: 教学意图说明（写进 DB ``note`` 列，给维护者看）。
    note: str = ""


def _square_vertices(
    *, cx: float = 0.5, cy: float = 0.5, half: float = 0.22
) -> list[tuple[float, float]]:
    """轴对齐正方形顶点（归一化，y 向下），**刻意不做任何微扰**（ADR-0061 §Q 决策 A）。

    理由：这类题考的就是「**几条**」这个数，视觉上规整反而更清楚；任何「稍微转一点
    更像图」的微扰都会让学生数错。故此函数**不接受** rotation 参数（要转就整体旋转
    画布，别动顶点）。
    """
    return [
        (cx - half, cy - half),
        (cx + half, cy - half),
        (cx + half, cy + half),
        (cx - half, cy + half),
    ]


# 内置图形种子。顶点逐点照搬原型（prototypes/reflection_demo.html），迁移时不得重绘，
# 确保视觉零回归。顺序 = 图库浏览序（前端画廊按 key 排序，见 list_figure_library）。
BUILTIN_FIGURE_SEED: tuple[SeedFigure, ...] = (
    SeedFigure(
        key="house",
        label="房子",
        note="房子：五边形（底 + 两腰 + 屋顶），竖直的对称轴。",
        vertices=[
            (0.30, 0.70),
            (0.70, 0.70),
            (0.70, 0.45),
            (0.50, 0.25),
            (0.30, 0.45),
        ],
    ),
    SeedFigure(
        key="kite",
        label="风筝",
        note="风筝：菱形，竖直的对称轴。",
        vertices=[
            (0.50, 0.20),
            (0.72, 0.50),
            (0.50, 0.80),
            (0.28, 0.50),
        ],
    ),
    SeedFigure(
        key="arrow",
        label="箭头",
        note=(
            "箭头：横向（**故意画成水平对称**）——学生打开的初始轴是竖直的，"
            "需要自己转 90° 才能重合，正是「动手找轴」的教学点。"
        ),
        vertices=[
            (0.20, 0.42),
            (0.62, 0.42),
            (0.62, 0.30),
            (0.82, 0.50),
            (0.62, 0.70),
            (0.62, 0.58),
            (0.20, 0.58),
        ],
    ),
    # 平行四边形：**刻意画成不对称**（错切：上边中点 0.50 / 下边中点 0.62），
    # 用来演示「不是轴对称图形」。若被「修正」成矩形，这道题就失去判断意义
    # ——所以它的顶点不可动。
    SeedFigure(
        key="para",
        label="平行四边形",
        note=(
            "平行四边形：**刻意画成不对称**（错切：上边中点 0.50 / 下边 0.62），"
            "用来演示「不是轴对称图形」。若被「修正」成矩形，这道题就失去判断意义"
            "——所以它的顶点不可动。"
        ),
        vertices=[
            (0.30, 0.40),
            (0.70, 0.40),
            (0.82, 0.70),
            (0.42, 0.70),
        ],
    ),
    # 正方形：**程序生成**（ADR-0061 §Q 决策 A：轴对齐、零微扰）。
    # 为什么它可以程序生成而 para 不行：正方形的几何定义**唯一且无歧义**
    # （四边等长、四角直角），任何实现都得到同一个图形；而 para 的「不对称」是
    # **教学设计的意图**，算法只会把它"修好"。
    SeedFigure(
        key="square",
        label="正方形",
        note=(
            "正方形：**程序生成**（ADR-0061 §Q 决策 A：轴对齐、零微扰）。"
            "几何定义唯一且无歧义，故顶点由函数算出；para 的「不对称」是教学设计"
            "意图，绝不能由算法生成。"
        ),
        vertices=_square_vertices(),
    ),
    # 等腰三角形：apex 朝上、底边水平；顶点刻意落在 x=0.5 中线上，左右底点对称。
    SeedFigure(
        key="iso_triangle",
        label="等腰三角形",
        note="等腰三角形：apex 朝上、底边水平；顶点落在 x=0.5 中线上，左右底点对称。",
        vertices=[
            (0.50, 0.22),
            (0.26, 0.78),
            (0.74, 0.78),
        ],
    ),
    # 等边三角形：顶点按等边几何算（底 0.5、高 0.5·√3/2≈0.433 → apex y = 0.78-0.433）。
    SeedFigure(
        key="eq_triangle",
        label="等边三角形",
        note="等边三角形：底 0.5、高 ≈0.433，apex 落在底边中点正上方。",
        vertices=[
            (0.50, 0.347),
            (0.25, 0.78),
            (0.75, 0.78),
        ],
    ),
    SeedFigure(
        key="rectangle",
        label="矩形",
        note="矩形（长方形）：水平与竖直两条对称轴。",
        vertices=[
            (0.22, 0.35),
            (0.78, 0.35),
            (0.78, 0.65),
            (0.22, 0.65),
        ],
    ),
    SeedFigure(
        key="iso_trapezoid",
        label="等腰梯形",
        note="等腰梯形：上下边都居中于 x=0.5 → 一条竖直对称轴。",
        vertices=[
            (0.38, 0.40),
            (0.62, 0.40),
            (0.82, 0.72),
            (0.18, 0.72),
        ],
    ),
    # 任意梯形（非等腰）：上下边中点错开 → 真无对称轴，作干扰项。
    SeedFigure(
        key="trapezoid_gen",
        label="任意梯形",
        note="任意梯形（非等腰）：上下边中点错开 → 无对称轴，作干扰项。",
        vertices=[
            (0.30, 0.40),
            (0.62, 0.40),
            (0.86, 0.72),
            (0.20, 0.72),
        ],
    ),
    # 一般四边形：刻意不规则 → 真无对称轴，作为「不是轴对称」的干扰项。
    SeedFigure(
        key="quad_gen",
        label="一般四边形",
        note="一般四边形：刻意不规则 → 无对称轴，作干扰项。",
        vertices=[
            (0.25, 0.30),
            (0.80, 0.40),
            (0.70, 0.74),
            (0.30, 0.66),
        ],
    ),
)


def figure_geometry(session: Session, key: str | None) -> dict[str, Any] | None:
    """按 key 从 ``figure_library`` 表取几何（ADR-0083）：``{key,label,points,edges}``。

    返回值是**纯几何**（无 axis 字段）；未命中返回 ``None``——调用方据此降级为
    「不给图」，绝不兜底到某个内置图形（那是编造，ADR-0061 §U 反臆造纪律）。
    """
    if not key:
        return None
    row = session.exec(
        select(FigureLibrary).where(FigureLibrary.key == key)
    ).first()
    if row is None:
        return None
    return {
        "key": row.key,
        "label": row.label,
        "points": row.points or [],
        "edges": row.edges or [],
    }
