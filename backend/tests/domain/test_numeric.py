"""数值解析原语单测（numeric-01 / ADR-0071 第一轮）。

覆盖三类：等价、量纲不兼容判错、非数值回退。运行全绿即满足 ticket 验收。
"""

import pytest

from app.domain.numeric import NumericValue, numeric_equal, parse_numeric


# ── 等价类 ───────────────────────────────────────────────────────────
def test_length_with_bare_number_equal():
    # 「12厘米」与省略单位的「12」判等（学生按标准答案单位理解）。
    assert numeric_equal("12厘米", "12") is True
    v = parse_numeric("12厘米")
    assert isinstance(v, NumericValue)
    assert v.dimension == "length"
    assert float(v.to_base()) == pytest.approx(0.12)


def test_cross_unit_length_equivalence():
    # 同量纲不同单位经基准换算后等价。
    assert numeric_equal("12厘米", "0.12米") is True
    assert numeric_equal("12厘米", "120毫米") is True
    assert numeric_equal("0.12米", "120毫米") is True


def test_fraction_forms_equivalent():
    # 真/假分数与小数约分后一致。
    assert numeric_equal("1/2", "2/4") is True
    assert numeric_equal("1/2", "0.5") is True
    assert numeric_equal("2/4", "0.5") is True
    assert parse_numeric("2/4").value == parse_numeric("1/2").value


def test_mixed_number_equivalent():
    assert numeric_equal("3又1/2", "3.5") is True
    assert parse_numeric("3又1/2").value == parse_numeric("3.5").value


def test_third_vs_decimal_loose_tolerance():
    # 粗近似需放宽 eps（默认 1e-9/1e-6 仅覆盖浮点舍入）。
    assert numeric_equal("1/3", "0.333", eps=5e-3) is True
    # 但默认严格容差下不误判。
    assert numeric_equal("1/3", "0.333") is False


def test_counting_unit_equivalent_to_bare():
    # 含未登记单位「个」按无量纲处理，仅比系数。
    assert numeric_equal("5个", "5") is True


def test_negative_number():
    v = parse_numeric("-3")
    assert v is not None and v.value == -3


# ── 量纲不兼容判错类 ──────────────────────────────────────────────────
def test_dimension_incompatible_false():
    assert numeric_equal("5cm", "5kg") is False
    assert numeric_equal("5厘米", "5千克") is False


def test_incompatible_not_equal_to_bare_of_other_dim():
    # 「5cm」(长度) 与「5」(无量纲) 兼容且仅比系数 → 相等；
    # 这里验证的是「带量纲 vs 异量纲」才判错，确认语义边界。
    assert numeric_equal("5cm", "5") is True  # 学生省略单位，按厘米理解
    assert numeric_equal("5kg", "5g") is False  # 同属重量但数量级不同


# ── 非数值回退类 ──────────────────────────────────────────────────────
@pytest.mark.parametrize("text", ["x=5", "π", "√2", "苹果", "一又二分之一", "", None])
def test_non_numeric_returns_none(text):
    assert parse_numeric(text) is None


def test_non_numeric_not_equal():
    assert numeric_equal("x=5", "5") is False
    assert numeric_equal("π", "3.14") is False
