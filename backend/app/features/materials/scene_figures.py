"""轴对称教学图形顶点库（ADR-0061 §O / ADR-0073 遗留 4）—— 几何数据的**唯一手写事实源**。

前端 `frontend/lib/shared/domain/figures.dart` **不再是第二份手写副本**，而是由
`frontend/scripts/gen_figures.py` 从本文件**生成**的产物（构建期生成，不是运行时
拉取）。为什么是"生成"而不是"运行时拉取"：整库画廊必须离线可用（tablet-first /
离线教室），改成运行时拉取会让「第一次打开是空的」变成常态。

为什么不让后端去读 Dart 文件：运行时后端不能读前端源码目录（部署形态不同），
而且顶点是**教学素材**（人工设计：para 刻意不对称、arrow 走水平轴），不是算法
产物——它必须落在某一处被人工维护，那就落在唯一一处。

⚠️ **改顶点只改这里**，然后重跑生成脚本（忘了跑会被 `--check` 拦住，CI 可见）。
几何漂移会直接让「是否轴对称」的判定变错（学生拖轴永远对不上）。

坐标归一化到 0..1、y 向下（与前端画布一致）。
"""
from __future__ import annotations

from dataclasses import field
from typing import Any, NamedTuple

from sqlmodel import Session, select

from app.db.models import FigureLibrary


class FigureShape(NamedTuple):
    """一个轴对称教学图形：归一化顶点 + 默认对称轴角度 + **全部**对称轴角度。"""

    key: str
    label: str
    #: [(x, y), ...]，x/y ∈ 0..1，y 向下；按序连成多边形。
    vertices: list[tuple[float, float]]
    #: 默认对称轴角度（度，0=水平、90=竖直）。arrow 是横向的→0°，其余立着→90°。
    default_axis_angle: float
    #: **全部**对称轴的角度（度）。「有几条对称轴」这类题要数它（ADR-0061 §Q）。
    #: 只有一条轴的图形就只放一个；顺序即讲解时的推荐演示顺序。
    axis_angles: list[float] = field(default_factory=list)
    #: 讲解这个图形**为什么长这样**的一句话（教学意图，非渲染数据）。
    #: 典型如「para 刻意错切成不对称——修好看就废了这道题」。此前这类说明只写在
    #: 前端注释里，改顶点的人看不到，于是「顺手修好看」的悲剧有真实发生路径。
    #: 现在它与顶点同属唯一手写源，并随生成脚本一起下发到前端，不会被漏掉。
    #: 刻意**不进** ``to_dict()``：它是给维护者看的，不是给渲染器消费的。
    note: str = ""

    @property
    def axis_count(self) -> int:
        """对称轴条数——「正方形有几条对称轴」的答案就是这个数。

        **如实返回**（平行四边形 = 0），不做「至少 1」的兜底：这份数据的唯一用途
        就是回答「有几条」，兜底会把「它没有对称轴」谎报成 1 条——那是**教错**。
        渲染器要的「初始轴」另有 ``default_axis_angle``，两者语义不同，别混。
        """
        return len(self.axis_angles)

    def to_dict(self) -> dict[str, Any]:
        """下发形态（前端 `SceneOptionItem` / `ReflectionSceneData` 消费）。

        ``points`` 用 ``[[x, y], ...]``（列表的列表）而非对象数组——前端按
        ``List<Offset>`` 消费，扁平数组省一层转换。
        """
        return {
            "key": self.key,
            "label": self.label,
            "points": [[x, y] for x, y in self.vertices],
            "defaultAxisAngle": self.default_axis_angle,
            "axisAngles": list(self.axis_angles),
            "axisCount": self.axis_count,
        }


def _square_vertices(
    *, cx: float = 0.5, cy: float = 0.5, half: float = 0.22
) -> list[tuple[float, float]]:
    """轴对齐正方形顶点（归一化，y 向下），**刻意不做任何微扰**（决策 A）。

    决策 A 的理由：这类题考的就是「**几条**」这个数。视觉上规整反而更清楚；
    任何「稍微转一点更像图」的随机/微扰都会让学生数错——浮点误差下对角线
    判定可能勉强通过但视觉上明显歪，教学上是负收益。故此函数**不接受**
    rotation 参数（要转就整体旋转画布，别动顶点）。
    """
    return [
        (cx - half, cy - half),
        (cx + half, cy - half),
        (cx + half, cy + half),
        (cx - half, cy + half),
    ]


# 内置图形预设集。顶点逐点照搬前端枚举（prototypes/reflection_demo.html 原型），
# 迁移时不得重绘，确保视觉零回归。
FIGURES: tuple[FigureShape, ...] = (
    FigureShape(
        key="house",
        label="房子",
        note="房子：五边形（底 + 两腰 + 屋顶），竖直对称。",
        vertices=[
            (0.30, 0.70),
            (0.70, 0.70),
            (0.70, 0.45),
            (0.50, 0.25),
            (0.30, 0.45),
        ],
        default_axis_angle=90,
        axis_angles=[90],
    ),
    FigureShape(
        key="kite",
        label="风筝",
        note="风筝：菱形，竖直对称。",
        vertices=[
            (0.50, 0.20),
            (0.72, 0.50),
            (0.50, 0.80),
            (0.28, 0.50),
        ],
        default_axis_angle=90,
        axis_angles=[90],
    ),
    FigureShape(
        key="arrow",
        label="箭头",
        note=(
            "箭头：横向（**故意水平对称**）→ 默认轴 0°。\n"
            "唯一那条轴是水平线（竖直方向上下不对称）。"
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
        default_axis_angle=0,
        # 横向箭头：唯一那条轴是水平线。竖直方向不是（上下不对称）。
        axis_angles=[0],
    ),
    # 平行四边形：**刻意画成不对称**（错切：上边中点 0.50 / 下边中点 0.62），
    # 用来演示「不是轴对称图形」。若被「修正」成矩形，这道题就废了——
    # 所以它的顶点不可动，且 axis_angles 为空（真的没有对称轴）。
    FigureShape(
        key="para",
        label="平行四边形",
        note=(
            "平行四边形：**刻意画成不对称**（错切：上边中点 0.50 / 下边 0.62），\n"
            "用来演示「不是轴对称图形」。若被「修正」成矩形，这道题就失去判断意义\n"
            "——所以它的顶点不可动，且对称轴列表为空（真的没有对称轴）。"
        ),
        vertices=[
            (0.30, 0.40),
            (0.70, 0.40),
            (0.82, 0.70),
            (0.42, 0.70),
        ],
        default_axis_angle=90,
        axis_angles=[],
    ),
    # 正方形：**程序生成**（ADR-0061 §Q 决策 A：轴对齐、零微扰）。
    # 为什么它可以程序生成而 para 不行：正方形的几何定义**唯一且无歧义**
    # （四边等长、四角直角），任何实现都必然得到一个 4 条对称轴的图形；
    # 而 para 的「不对称」是**教学设计的意图**，算法只会把它"修好"。
    # 4 条轴：竖(90) / 横(0) / 两条对角(45,135)——「有几条对称轴」的答案就是 4。
    FigureShape(
        key="square",
        label="正方形",
        note=(
            "正方形：**程序生成**（ADR-0061 §Q 决策 A：轴对齐、零微扰）。\n"
            "为什么它可以程序生成而 para 不行：正方形的几何定义**唯一且无歧义**，\n"
            "任何实现都必然得到一个 4 条对称轴的图形；而 para 的「不对称」是\n"
            "**教学设计的意图**，算法只会把它修好。\n"
            "4 条轴：竖(90)/横(0)/两条对角(45,135)——「有几条」的答案就是 4。"
        ),
        vertices=_square_vertices(),
        default_axis_angle=90,
        axis_angles=[90, 0, 45, 135],
    ),
    # 等腰三角形： apex 朝上、底边水平 → 仅一条竖直对称轴（ADR-0061 §O 常用干扰/正例）。
    # 顶点刻意落在 x=0.5 中线上，左右底点对称，确保真的只有 1 条轴。
    FigureShape(
        key="iso_triangle",
        label="等腰三角形",
        note=(
            "等腰三角形：apex 朝上、底边水平 → 仅一条竖直对称轴（1 条轴）。\n"
            "顶点刻意落在 x=0.5 中线上，左右底点对称，确保真的只有 1 条轴。"
        ),
        vertices=[
            (0.50, 0.22),
            (0.26, 0.78),
            (0.74, 0.78),
        ],
        default_axis_angle=90,
        axis_angles=[90],
    ),
    # 等边三角形： apex 朝上、底边水平；3 条对称轴（竖直 + 两条 ±60° 的腰中线）。
    # 顶点按等边几何算：底 0.5、高 0.5·√3/2≈0.433 → apex y = 0.78-0.433。
    FigureShape(
        key="eq_triangle",
        label="等边三角形",
        note=(
            "等边三角形：apex 朝上、底边水平；\n"
            "3 条对称轴（竖直 + 两条 ±60° 的腰中线）。"
        ),
        vertices=[
            (0.50, 0.347),
            (0.25, 0.78),
            (0.75, 0.78),
        ],
        default_axis_angle=90,
        axis_angles=[90, 30, 150],
    ),
    # 矩形（长方形）：水平 + 竖直两条对称轴 → 2 条轴。
    FigureShape(
        key="rectangle",
        label="矩形",
        note="矩形（长方形）：水平 + 竖直两条对称轴 → 2 条轴。",
        vertices=[
            (0.22, 0.35),
            (0.78, 0.35),
            (0.78, 0.65),
            (0.22, 0.65),
        ],
        default_axis_angle=90,
        axis_angles=[90, 0],
    ),
    # 等腰梯形：上下边都居中于 x=0.5 → 仅一条竖直对称轴（1 条轴）。
    FigureShape(
        key="iso_trapezoid",
        label="等腰梯形",
        note=(
            "等腰梯形：上下边都居中于 x=0.5\n"
            "→ 仅一条竖直对称轴（1 条轴）。"
        ),
        vertices=[
            (0.38, 0.40),
            (0.62, 0.40),
            (0.82, 0.72),
            (0.18, 0.72),
        ],
        default_axis_angle=90,
        axis_angles=[90],
    ),
    # 任意梯形（非等腰）：上下边中点错开（上 0.46 / 下 0.53）→ 真无对称轴（0 条轴）。
    # 同 para 的设计意图：它就是「不是轴对称」的干扰项，顶点不可动、axis_angles 空。
    FigureShape(
        key="trapezoid_gen",
        label="任意梯形",
        note="任意梯形（非等腰）：上下边中点错开 → 真无对称轴（0 条轴），作干扰项。",
        vertices=[
            (0.30, 0.40),
            (0.62, 0.40),
            (0.86, 0.72),
            (0.20, 0.72),
        ],
        default_axis_angle=90,
        axis_angles=[],
    ),
    # 一般四边形：刻意不规则，真无对称轴（0 条轴），作为「不是轴对称」的干扰项。
    FigureShape(
        key="quad_gen",
        label="一般四边形",
        note="一般四边形：刻意不规则，真无对称轴（0 条轴），作干扰项。",
        vertices=[
            (0.25, 0.30),
            (0.80, 0.40),
            (0.70, 0.74),
            (0.30, 0.66),
        ],
        default_axis_angle=90,
        axis_angles=[],
    ),
)


_BY_KEY: dict[str, FigureShape] = {f.key: f for f in FIGURES}


def figure_by_key(key: str | None) -> FigureShape | None:
    """按 key 取图形；未命中返回 ``None``（调用方据此降级，不静默回落）。

    ⚠️ ADR-0083 后本函数**仅供种子 / 迁移与纯函数测试**使用（读代码常量
    ``FIGURES``）。运行时的几何来源已改为 ``figure_library`` 表——走
    :func:`figure_geometry`（查 DB），不再回查代码常量。
    """
    if not key:
        return None
    return _BY_KEY.get(key)


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
