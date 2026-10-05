"""题面 → 场景输入抽取（ADR-0061 §M 第1 步 / 决策 2）。

知识点模板给的是**默认**参数（如房子 + 竖轴 90°），但题面可能讲的是别的图形、
别的轴。这里的职责是把题面里的图形/角度抽出来，作为 ``fuse_scene_spec`` 的
``overrides`` 覆盖默认值——让场景贴合**这道题**，而不是贴合模板。

设计取舍（都是为了不臆造）：
- **只抽「抽得到且不矛盾」的**：题面明确出现某个图形词→ 覆盖 ``figure``；
  题面给出角度数值 → 覆盖 ``axisAngle``。抽不到就**不覆盖**，沿用模板默认。
- **不猜坐标**：``axisX/axisY`` 是归一化对称轴位置，题面极少精确表述，
  强行推断等于编造 → 永远不从题面抽，只由教师在调参面板里手摆。
- **选择题只取一个场景**：选项里多个图形时，取**第一个**命中的图形作为演示对象
  （题面若指定了「下图/如图」类图形，以题面优先）。逐选项各配一个场景需要
  SceneSpec 表达「候选图形集合 + 判定哪几个对称」，那是**新 kind**（§M 第 3 步），
  不在本函数的能力范围内——单 kind 场景结构上只能演示一个图形。

纯函数、无IO、无模型调用（契合 ADR-0039 离线纪律）：抽不出来就返回空 dict，
上层照旧用模板默认值。
"""
from __future__ import annotations

import re
from typing import Any

from app.features.materials.scene_figures import figure_by_key

# 题面/选项里出现即认为「讲的是这个图形」的中英词表。
# key与 `scene_figures.FIGURES` 的 key 一一对应——识别出 key 后由 `scene_figures`
# 查出顶点，**本模块不持有任何几何数据**。
# 顺序有意义：先匹配更具体的词，避免「平行四边形」被「四边形」类词抢走。
_FIGURE_WORDS: list[tuple[str, tuple[str, ...]]] = [
    ("house", ("房子", "房屋", "house", "小房子")),
    ("kite", ("风筝", "kite")),
    ("arrow", ("箭头", "箭头形", "arrow")),
    ("para", ("平行四边形", "平行四边型", "parallelogram", "para")),
    # 正方形（ADR-0061 §Q）：**程序生成**的规则图形，几何必然正确。
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

# 题面里带单位的角度，如「45°」「60度」「90 °」。
# 负号必须一并捕获：`-30°` 若丢掉符号会被当成 30°，把对称轴画到镜像位置——
# 场景与题目不符比不给场景更糟（ADR-0061 §M）。
_ANGLE_RE = re.compile(r"([+-]?\d{1,3}(?:\.\d+)?)\s*(?:°|度)")


def extract_scene_inputs(
    *,
    stem: str | None,
    options: list[str] | None = None,
) -> dict[str, Any]:
    """从题面抽场景输入覆盖值（ADR-0061 §M）。

    返回可安全传给 :func:`fuse_scene_spec` 的 ``overrides``（可能为空 dict）。
    **抽不到就返回空 dict**，绝不返回猜测值——宁可让场景沿用教师配的默认值，
    也不要给一个与题目无关的图形（那比没有场景更糟：会教错）。

    抽取项：
    - ``figure``：题面（优先）或选项里命中的第一个图形词；
    - ``axisAngle``：题面里出现的**第一个**角度值。选择题里若题面与选项的角度
      不一致，以题面为准（题面才是这道题的主语）。
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

    # —— figure 命中时必须**连带下发顶点**（ADR-0061 §Q）——
    # 只覆盖 `figure` 是不行的：教师配的模板里存着他选的图形顶点（可能是房子），
    # 而前端 `fromSpec` 的几何优先级是「points > figure 预设」→ 只改figure
    # 的话，画面上仍是**房子**，题干却在讲正方形。图形与几何必须同时换。
    if "figure" in overrides:
        shape = figure_by_key(overrides["figure"])
        if shape is not None:
            overrides["points"] = [[x, y] for x, y in shape.vertices]
            # 如实下发（平行四边形就是空列表= 0 条轴）；渲染要的初始轴另有
            # defaultAxisAngle，语义不同，别用 `or [default]` 兜底。
            overrides["axisAngles"] = list(shape.axis_angles)
            overrides["axisCount"] = shape.axis_count

    # —— axisAngle：题面里的第一个角度；题面没有再看选项 ——
    m = _ANGLE_RE.search(stem)
    if m is None and opts:
        m = _ANGLE_RE.search(opts)
    if m is not None:
        try:
            angle = float(m.group(1))
        except ValueError:  # pragma: no cover - 正则已保证可转
            angle = None
        # 只接受 0..180：对折动画的角度域，超域的值说明题面在讲别的东西
        # （如「360度旋转」是平移/旋转题，不是轴对称），不覆盖。
        if angle is not None and 0 <= angle <= 180:
            overrides["axisAngle"] = angle

    return overrides


def extract_option_group(options: list[str] | None) -> dict[str, Any] | None:
    """选择题 → 「每个选项一个可交互图形」的选项组（ADR-0061 §O）。

    一道「下列图形哪些是轴对称」的题，每个选项本身就是一个图形。学生要**逐个
    亲手试**（旋转/平移对称轴看能否重合），而不是看程序报答案。所以这里为每个
    能识别出图形的选项生成一项，附上**顶点**（来自 ``scene_figures``，本模块不碰
    几何数据），前端按项渲染多个独立场景。

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
        shape = figure_by_key(key)
        if shape is None:  # pragma: no cover - key 来自同一张表
            return None
        items.append(
            {
                # 选项标号只用于界面定位（"A"/"B"…），不参与任何判定。
                "label": _option_label(opt, idx),
                "caption": shape.label,
                "figureKey": shape.key,
                "points": [[x, y] for x, y in shape.vertices],
                "defaultAxisAngle": shape.default_axis_angle,
            }
        )
    return {"items": items}


def _match_figure(text: str) -> str | None:
    """文本里命中哪个内置图形；未命中返回 ``None``。"""
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
