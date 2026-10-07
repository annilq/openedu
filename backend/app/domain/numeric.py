"""数值等价判分原语（numeric-equivalence-grading 第一轮，ADR-0071）。

判分所需的**纯函数层**：把学生 / 标准答案中的「数值 + 单位」文本解析为可比较的
数值，并在量纲兼容下做容差比较。本模块只依赖标准库
（``re`` / ``fractions``），**不引入 sympy / pint / numpy**。

设计要点：
- 解析成功返回 :class:`NumericValue` ``(value, dimension, scale)``：``value`` 是数字**系数**，
  ``dimension`` 为量纲或 None，``scale`` 是「该单位 → 基准单位」的有理数系数
  （长度→米、重量→千克、时间→秒、角度→度、货币→元）。
- 比较在 :func:`numeric_equal` 内进行：同量纲不同单位经 ``scale`` 折算到基准单位后比对
  （``12厘米`` == ``0.12米`` == ``120毫米``）；任一侧无量纲（纯数字 / 含未登记单位如「个」）
  视为兼容、仅比系数——这样 ``12厘米`` 与 ``12`` 判等，``5个`` 与 ``5`` 判等。
- 量纲不兼容（如 ``5cm`` vs ``5kg``）``numeric_equal`` 返回 ``False``。
- 非数值文本（含字母变量 / 等式 / ``π`` / ``√`` / 纯中文）返回 ``None``，交由上层回退。
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from fractions import Fraction
from typing import Final

# 单位 → (量纲, 折算到基准单位的 Fraction 系数)
_UNIT_TABLE: Final[dict[str, tuple[str, Fraction]]] = {
    # 长度 → 米
    "米": ("length", Fraction(1)),
    "m": ("length", Fraction(1)),
    "分米": ("length", Fraction(1, 10)),
    "dm": ("length", Fraction(1, 10)),
    "厘米": ("length", Fraction(1, 100)),
    "cm": ("length", Fraction(1, 100)),
    "毫米": ("length", Fraction(1, 1000)),
    "mm": ("length", Fraction(1, 1000)),
    # 重量 → 千克
    "千克": ("weight", Fraction(1)),
    "公斤": ("weight", Fraction(1)),
    "kg": ("weight", Fraction(1)),
    "克": ("weight", Fraction(1, 1000)),
    "g": ("weight", Fraction(1, 1000)),
    # 时间 → 秒
    "时": ("time", Fraction(3600)),
    "小时": ("time", Fraction(3600)),
    "分": ("time", Fraction(60)),
    "分钟": ("time", Fraction(60)),
    "秒": ("time", Fraction(1)),
    "s": ("time", Fraction(1)),
    # 角度 → 度
    "度": ("angle", Fraction(1)),
    # 货币 → 元
    "元": ("currency", Fraction(1)),
    "角": ("currency", Fraction(1, 10)),
    # 注：「分」在中文里既指时间「分钟」也指货币「分」，键不可重复；
    # 货币分极少作为判分量级，故此处仅保留时间「分」，货币用「角/元」即可。
}

# 数字主体 + 可选单位后缀，整体 `$` 锚定，避免分支只吃掉前缀（如「3又1/2」被小数分支截断为「3」）。
# 分支顺序：分数 → 整数/小数 → 整数/带分数；单位后缀统一由末尾 `(?P<unit>...)` 捕获。
_BODY_RE = re.compile(
    r"^(?P<neg>-?)"  # 负号（含 ASCII 连字符；全角负号已在 normalize 中归一）
    r"(?:"
    r"(?P<num>\d+)/(?P<den>\d+)"  # 分数 a/b
    r"|"
    r"(?P<dec>\d+(?:\.\d+)?)"  # 整数 / 小数
    r"|"
    r"(?P<mi>\d+)(?:又(?P<mn>\d+)/(?P<md>\d+))?"  # 整数 或 带分数 a又b/c
    r")"
    r"(?P<unit>[一-鿿a-zA-Z]*)$"  # 可选单位后缀（CJK 或拉丁）
)

_CJK_RE = re.compile(r"[一-鿿]")


def _is_all_cjk(text: str) -> bool:
    """后缀是否全为 CJK（量词如「个/辆」，非单位时按无量纲处理）。"""
    return bool(text) and all(_CJK_RE.match(ch) for ch in text)


@dataclass(frozen=True)
class NumericValue:
    """解析后的数值：系数 ``value``、量纲 ``dimension``、单位→基准系数 ``scale``。"""

    value: Fraction
    dimension: str | None
    scale: Fraction = Fraction(1)

    def to_base(self) -> Fraction:
        """折算到基准单位的数值（无量纲返回系数本身）。"""
        return self.value * self.scale


def _normalize_text(text: str) -> str:
    """归一化空白与全角符号，便于正则匹配。"""
    text = text.replace("－", "-").replace("−", "-").replace("–", "-")
    return text.strip()


def parse_numeric(text: str | None) -> NumericValue | None:
    """解析「数值 + 单位」文本；非数值返回 ``None``。

    支持的形态：整数、小数、真/假分数 ``a/b``、带分数 ``a又b/c``、负号；
    可带长度/重量/时间/角度/货币单位（含常见拉丁别名）。

    非数值判定：含拉丁字母（变量 ``x``）、等式 ``=``、符号 ``π`` / ``√``、
    或纯中文（无数字）一律返回 ``None``，交由上层回退到原有判分逻辑。
    """
    if text is None:
        return None
    s = _normalize_text(text)
    if not s:
        return None
    # 非数值信号的快速排除（等式 / 符号）。
    if any(ch in s for ch in "=π√"):
        return None
    # 纯中文（无任何数字）视为非数值。
    if not any(ch.isdigit() for ch in s):
        return None

    m = _BODY_RE.match(s)
    if m is None:
        return None

    neg = -1 if m.group("neg") else 1
    if m.group("mi") is not None:
        whole = int(m.group("mi"))
        if m.group("mn") is not None:
            value = Fraction(whole) + Fraction(int(m.group("mn")), int(m.group("md")))
        else:
            value = Fraction(whole)
    elif m.group("num") is not None:
        den = int(m.group("den"))
        if den == 0:
            return None
        value = Fraction(int(m.group("num")), den)
    else:
        value = Fraction(m.group("dec"))
    value *= neg

    # 末尾单位后缀（已随整体正则捕获，无需再切片）。
    suffix = m.group("unit") or ""
    if suffix:
        unit = _UNIT_TABLE.get(suffix)
        if unit is not None:
            dimension, scale = unit
            return NumericValue(value=value, dimension=dimension, scale=scale)
        # 全 CJK 的量词（个/辆/条…）非登记单位，按无量纲处理，仅保留系数。
        if _is_all_cjk(suffix):
            return NumericValue(value=value, dimension=None, scale=Fraction(1))
        # 其余（含未登记拉丁字母，如「5x」「12abc」）视为非数值。
        return None
    return NumericValue(value=value, dimension=None, scale=Fraction(1))


def numeric_equal(
    answer: str | None,
    submission: str | None,
    *,
    eps: float = 1e-9,
    rel: float = 1e-6,
) -> bool:
    """量纲兼容下的容差等价比较。

    - 任一解析失败 → ``False``（非数值答案交由上层回退）。
    - 两侧均带量纲且不同 → ``False``（量纲不兼容）。
    - 两侧均带量纲且相同 → 折算到基准单位后按容差比对（不同单位可跨单位等价）。
    - 任一侧无量纲 → 仅比系数（学生省略单位时按标准答案单位理解）。
    - 绝对容差 ``eps`` 与相对容差 ``rel`` 双判（默认 1e-9 / 1e-6，覆盖浮点舍入）；
      粗近似（如 ``1/3`` vs ``0.333``）需调用方放宽 ``eps``。
    """
    pa = parse_numeric(answer)
    pb = parse_numeric(submission)
    if pa is None or pb is None:
        return False
    if pa.dimension is not None and pb.dimension is not None:
        if pa.dimension != pb.dimension:
            return False
        fa = float(pa.to_base())
        fb = float(pb.to_base())
    else:
        fa = float(pa.value)
        fb = float(pb.value)
    diff = abs(fa - fb)
    scale = max(abs(fa), abs(fb))
    return diff <= eps or diff <= rel * scale
