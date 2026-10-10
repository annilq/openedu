"""题面 → 场景输入抽取（ADR-0061 §M / ADR-0083）。

知识点模板给的是默认讲解，但题面可能讲的是**别的图形**。这里的职责是把题面里的
图形名抽出来，告诉上层「这道题要演示哪个图形」——几何由上层按 key 查图库
``figure_library`` 表取（ADR-0083：几何事实源在 DB，本模块不持有任何坐标）。

设计取舍（都是为了不臆造）：
- **只抽「抽得到且不矛盾」的**：题面明确出现某个图形词 → 命中该 key；抽不到就
  返回空 dict，上层沿用模板默认。
- **不再抽角度**（ADR-0083 决策 6）：对称轴初值归 kind 外壳统一给定，每条 scene
  不再各自存 axisAngle——故题面里的角度数值不再覆盖场景。
- **选择题只取一个场景**：选项里多个图形时，取**第一个**命中的图形作演示对象。
  逐选项各配一个场景走 :func:`extract_option_group`。

纯函数、无IO、无模型调用（契合 ADR-0039 离线纪律）：抽不出来就返回空 dict。
"""
from __future__ import annotations

import re
from typing import Any

from sqlmodel import Session

from app.features.materials.scene_figures import figure_geometry

# 题面/选项里出现即认为「讲的是这个图形」的中英词表。
# key与 `figure_library` 表的 key —— 内置 11 个图形的 key 一一对应；用户在画板
# 里自定义的图形没有词条，故只有内置图形能靠题面文本命中（这是有意的：题面识别
# 只认策展过的标准图形，避免误命中）。
# 顺序有意义：先匹配更具体的词，避免「平行四边形」被「四边形」类词抢走。
_FIGURE_WORDS: list[tuple[str, tuple[str, ...]]] = [
    ("house", ("房子", "房屋", "house", "小房子")),
    ("kite", ("风筝", "kite")),
    ("arrow", ("箭头", "箭头形", "arrow")),
    ("para", ("平行四边形", "平行四边型", "parallelogram", "para")),
    # 正方形（ADR-0061 §Q）：规整图形，几何必然正确。
    # 「正方形有几条对称轴」这类题题干里只有图形名、没有选项图形，靠的就是这条。
    ("square", ("正方形", "square")),
    # 以下为「下列图形哪些是轴对称」类选择题选项常见图形（ADR-0061 §O 选项组）。
    # 顺序靠前的是更具体的词，避免被更短的词抢走（如「等腰梯形」须先于广义「梯形」）。
    ("iso_triangle", ("等腰三角形", "等腰三角型")),
    ("eq_triangle", ("等边三角形", "正三角形")),
    ("rectangle", ("矩形", "长方形")),
    ("iso_trapezoid", ("等腰梯形",)),
    ("trapezoid_gen", ("任意梯形", "一般梯形")),
    ("quad_gen", ("一般四边形", "任意四边形")),
]


def extract_scene_inputs(
    *,
    stem: str | None,
    options: list[str] | None = None,
) -> dict[str, Any]:
    """从题面抽「要演示哪个图形」（ADR-0061 §M / ADR-0083）。

    返回 ``{"figure": <key>}`` 或空 dict（抽不到）。**抽不到就返回空 dict**，
    绝不返回猜测值——宁可让场景沿用教师配的默认图形，也不要给一个与题目无关的
    图形（那比没有场景更糟：会教错）。

    几何不在这里取：上层拿到 key 后经 :func:`figure_geometry` 查图库
    ``figure_library``（ADR-0083：几何事实源在 DB）。
    """
    overrides: dict[str, Any] = {}
    if not stem and not options:
        return overrides

    stem = stem or ""
    opts = " ".join(options or [])

    # —— figure：题面优先，其次选项 ——
    for name, words in _FIGURE_WORDS:
        if any(w in stem for w in words):
            overrides["figure"] = name
            break
    if "figure" not in overrides:
        for name, words in _FIGURE_WORDS:
            if any(w in opts for w in words):
                overrides["figure"] = name
                break

    return overrides


def extract_option_group(session: Session, options: list[str] | None) -> dict[str, Any] | None:
    """选择题 → 「每个选项一个可交互图形」的选项组（ADR-0061 §O）。

    一道「下列图形哪些是轴对称」的题，每个选项本身就是一个图形。学生要**逐个
    亲手试**（旋转/平移对称轴看能否重合），而不是看程序报答案。所以这里为每个
    能识别出图形的选项生成一项，附上**顶点 + 边**（来自图库 ``figure_library``，
    ADR-0083：几何事实源在 DB），前端按项渲染多个独立场景。

    **全-or- 无**：只要有**任何一项识别不出**，就整体返回 ``None``（退回单场景）。
    理由——宁可少一个交互演示，也不能让某个选项配一个与题目无关的图形（那是在
    教错，学生会把「图不对」当成「这题答错了」）。半套选项组比没有更容易误导。

    单个选项文字里出现多个图形词时取**第一个**命中（:func:`extract_scene_inputs`
    同一口径）。
    """
    if not options or len(options) < 2:
        return None
    items: list[dict[str, Any]] = []
    for idx, opt in enumerate(options):
        key = _match_figure(opt or "")
        if key is None:
            return None
        geom = figure_geometry(session, key)
        if geom is None:  # pragma: no cover - key 来自同一张表
            return None
        items.append(
            {
                # 选项标号只用于界面定位（"A"/"B"…），不参与任何判定。
                "label": _option_label(opt, idx),
                "caption": geom["label"],
                "points": geom["points"],
                "edges": geom["edges"],
            }
        )
    return {"items": items}


def _match_figure(text: str) -> str | None:
    """文本里命中哪个内置图形 key；未命中返回 ``None``。"""
    for name, words in _FIGURE_WORDS:
        if any(w in text for w in words):
            return name
    return None


def _option_label(opt: str, idx: int) -> str:
    """选项标号：优先用原文自带的「A.」「B、」等前缀，否则退回序号字母。"""
    m = re.match(r"\s*([A-Da-d])\s*[.、,，)）]", opt or "")
    if m:
        return m.group(1).upper()
    return chr(ord("A") + idx)
