"""题面 → 场景输入抽取（ADR-0061 §M / ADR-0083 / ADR-0091）。

知识点模板给的是默认讲解，但题面可能讲的是**别的图形**。这里的职责是把题面里的
图形名抽出来，告诉上层「这道题要演示哪个图形」——几何由上层按 key 查图库
``figure_library`` 表取（ADR-0083：几何事实源在 DB，本模块不持有任何坐标）。

设计取舍（都是为了不臆造）：
- **只抽「抽得到且不矛盾」的**：题面明确出现某个图形词 → 命中该 key；抽不到就
  返回空 dict，上层沿用模板默认。
- **不再抽角度**（ADR-0083 决策 6）：对称轴初值归 kind 外壳统一给定，每条 scene
  不再各自存 axisAngle——故题面里的角度数值不再覆盖场景。
- **只认题面，不扫选项文字**（ADR-0091 ticket 02）：「扫选项文字反猜图形」的代码
  路径已整体删除——逐选项图形改由 AI 链路「模型引用身份键 + 盖章」接回（模型说
  哪个选项是哪个图形，后端只按身份键盖章几何），文本匹配反猜那一套不再复生。

纯函数、无IO、无模型调用（契合 ADR-0039 离线纪律）：抽不出来就返回空 dict。
"""
from __future__ import annotations

from typing import Any

# 题面里出现即认为「讲的是这个图形」的中英词表。
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
    # 以下为「下列图形哪些是轴对称」类选择题常见图形（选项组由 AI 链路接回，
    # 见模块 docstring；这里仍供题面直点图形名时命中）。
    # 顺序靠前的是更具体的词，避免被更短的词抢走（如「等腰梯形」须先于广义「梯形」）。
    ("iso_triangle", ("等腰三角形", "等腰三角型")),
    ("eq_triangle", ("等边三角形", "正三角形")),
    ("rectangle", ("矩形", "长方形")),
    ("iso_trapezoid", ("等腰梯形",)),
    ("trapezoid_gen", ("任意梯形", "一般梯形")),
    ("quad_gen", ("一般四边形", "任意四边形")),
]


def extract_scene_inputs(*, stem: str | None) -> dict[str, Any]:
    """从题面抽「要演示哪个图形」（ADR-0061 §M / ADR-0083 / ADR-0091）。

    返回 ``{"figure": <key>}`` 或空 dict（抽不到）。**抽不到就返回空 dict**，
    绝不返回猜测值——宁可让场景沿用教师配的默认图形，也不要给一个与题目无关的
    图形（那比没有场景更糟：会教错）。

    **只扫题面**：选项文字不再参与反猜（ADR-0091 ticket 02 删除该路径）——
    逐选项图形改由 AI 链路以「模型引用身份键 + 盖章」提供，文本匹配不复活。

    几何不在这里取：上层拿到 key 后经 :func:`figure_geometry` 查图库
    ``figure_library``（ADR-0083：几何事实源在 DB）。
    """
    overrides: dict[str, Any] = {}
    if not stem:
        return overrides
    for name, words in _FIGURE_WORDS:
        if any(w in stem for w in words):
            overrides["figure"] = name
            break
    return overrides
