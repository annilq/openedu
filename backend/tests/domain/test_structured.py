"""normalize_options 单测：模型不守 output_schema 时把选项揉成一串的兜底切分。"""
from __future__ import annotations

from app.domain.structured import normalize_options


def test_none_returns_none():
    assert normalize_options(None) is None


def test_non_list_non_str_returns_none():
    assert normalize_options({"a": 1}) is None


def test_already_clean_list_preserved():
    src = ["A. 苹果", "B. 香蕉", "C. 橙子"]
    assert normalize_options(src) == src


def test_combined_string_is_split():
    raw = "A. 平行四边形 B. 等腰三角形 C. 任意梯形 D. 一般四边形"
    out = normalize_options(raw)
    assert out == [
        "A. 平行四边形",
        "B. 等腰三角形",
        "C. 任意梯形",
        "D. 一般四边形",
    ]


def test_combined_string_with_cjk_punctuation():
    raw = "A、房子 B、风筝 C、箭头"
    assert normalize_options(raw) == ["A、房子", "B、风筝", "C、箭头"]


def test_combined_string_with_newlines():
    raw = "A. 苹果\nB. 香蕉\nC. 橙子"
    assert normalize_options(raw) == ["A. 苹果", "B. 香蕉", "C. 橙子"]


def test_single_element_list_with_multiple_options_is_flattened():
    raw = ["A. 苹果 B. 香蕉 C. 橙子"]
    assert normalize_options(raw) == ["A. 苹果", "B. 香蕉", "C. 橙子"]


def test_numeric_labels_split():
    raw = "1. 苹果 2. 香蕉 3. 橙子"
    assert normalize_options(raw) == ["1. 苹果", "2. 香蕉", "3. 橙子"]


def test_single_option_keeps_prefix():
    # 只有一个标号 → 不应切分，原样保留（含前缀）。
    assert normalize_options("A. 平行四边形") == ["A. 平行四边形"]


def test_empty_strings_dropped():
    assert normalize_options(["", "  ", None, "A. 苹果"]) == ["A. 苹果"]


def test_prefix_preserved_for_grading_consistency():
    # 切分只切分、不剥 "A." 前缀（答案字段也带前缀，剥离会破坏判题比对）。
    out = normalize_options("A. 苹果 B. 香蕉")
    assert out[0] == "A. 苹果"
    assert out[1] == "B. 香蕉"
