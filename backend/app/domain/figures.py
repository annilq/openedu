"""图形（Figure）——几何的**唯一载体**（ADR-0089 v3 / ADR-0091）。

三种写法的几何（场景规格顶层 / 选项条目 / 图形库）收敛到这一个类型：
一次演示 = ``kind`` 外壳 + 若干 :class:`Figure`（见 :mod:`app.domain.scene_spec`）。

本模块**只有数据**：不引 service / db / features，不碰 I/O，不含任何业务判定
（合法性由 :func:`app.domain.scene_spec.normalize_scene_spec` 判定）。

与前端 ``FigureShape``（``frontend/lib/shared/domain/figures.dart``）同构：
``key`` 身份 / ``label`` 中文名 / ``points`` 顶点 / ``edges`` 连接关系。
渲染只吃 ``points`` / ``edges``——``key`` 只作身份与溯源，**不按 key 回查图库**
（ADR-0083 决策 7：运行时零图库依赖）。
"""

from __future__ import annotations

from sqlmodel import SQLModel

__all__ = ["Figure"]


class Figure(SQLModel):
    """一个**可独立渲染的平面图形快照**：图库行的几何投影。

    与它挂在哪里无关——它不是「选项的图形」，它就是「图形」。同一个类型同时
    承担主图形（演示对象）与选项组条目（画廊卡片）。

    - ``key``：图库身份键，身份 / 溯源 / 校验用；渲染不消费。
    - ``label``：中文名（无障碍朗读 + 画廊标签）。⚠️ 对齐图库行与前端，不叫 caption。
    - ``points``：归一化顶点 ``[[x, y], ...]``，内联进 spec，离线可用。
    - ``edges``：顶点索引对 ``[[i, j], ...]``。
    """

    key: str
    label: str | None = None
    points: list[list[float]]
    edges: list[list[int]]
