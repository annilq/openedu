"""normalize_options / option_texts 单测（ADR-0089 决策 2）。

`normalize_options` 把模型产出的选项归一为**选项对象** ``{text, figure_key}``：
- 旧形（``str`` / ``list[str]``）→ tolerant read 包成对象，``figure_key=None``；
- 新形（``list[dict]``）→ 校验后保留 ``text`` 与身份键（``figure.key`` / ``figure_key``）；
- 模型不守 output_schema 把多个选项揉成一串 → 仍要切分成「每项一段」。

`option_texts` 是判题/展示路径读纯文字的唯一入口。
"""
from __future__ import annotations

from app.domain.structured import normalize_options, option_texts


def _texts(out: list[dict] | None) -> list[str]:
    return [o["text"] for o in (out or [])]


def test_none_returns_none():
    assert normalize_options(None) is None


def test_non_list_non_str_returns_none():
    assert normalize_options({"a": 1}) is None
    assert normalize_options(123) is None


def test_already_clean_list_preserved():
    src = ["A. 苹果", "B. 香蕉", "C. 橙子"]
    out = normalize_options(src)
    assert _texts(out) == src
    assert all(o["figure_key"] is None for o in out)


def test_combined_string_is_split():
    raw = "A. 平行四边形 B. 等腰三角形 C. 任意梯形 D. 一般四边形"
    assert _texts(normalize_options(raw)) == [
        "A. 平行四边形",
        "B. 等腰三角形",
        "C. 任意梯形",
        "D. 一般四边形",
    ]


def test_combined_string_with_cjk_punctuation():
    assert _texts(normalize_options("A、房子 B、风筝 C、箭头")) == ["A、房子", "B、风筝", "C、箭头"]


def test_combined_string_with_newlines():
    raw = "A. 苹果\nB. 香蕉\nC. 橙子"
    assert _texts(normalize_options(raw)) == ["A. 苹果", "B. 香蕉", "C. 橙子"]


def test_single_element_list_with_multiple_options_is_flattened():
    raw = ["A. 苹果 B. 香蕉 C. 橙子"]
    assert _texts(normalize_options(raw)) == ["A. 苹果", "B. 香蕉", "C. 橙子"]


def test_numeric_labels_split():
    assert _texts(normalize_options("1. 苹果 2. 香蕉 3. 橙子")) == ["1. 苹果", "2. 香蕉", "3. 橙子"]


def test_single_option_keeps_prefix():
    # 只有一个标号 → 不应切分，原样保留（含前缀）。
    assert _texts(normalize_options("A. 平行四边形")) == ["A. 平行四边形"]


def test_empty_strings_dropped():
    assert _texts(normalize_options(["", "  ", None, "A. 苹果"])) == ["A. 苹果"]


def test_prefix_preserved_for_grading_consistency():
    # 切分只切分、不剥 "A." 前缀（答案字段也带前缀，剥离会破坏判题比对）。
    out = normalize_options("A. 苹果 B. 香蕉")
    assert out is not None
    assert out[0]["text"] == "A. 苹果"
    assert out[1]["text"] == "B. 香蕉"


# ───────────────────── 对象形态 / tolerant read ─────────────────────


def test_dict_options_keep_text_and_figure_key():
    out = normalize_options(
        [
            {"text": "A. 正方形", "figure": {"key": "square"}},
            {"text": "B. 平行四边形", "figure": {"key": "para"}},
        ]
    )
    assert out is not None
    assert [(o["text"], o["figure_key"]) for o in out] == [
        ("A. 正方形", "square"),
        ("B. 平行四边形", "para"),
    ]


def test_dict_options_accept_bare_figure_key_and_bare_string():
    """tolerant read：``figure_key`` 直给 / ``figure`` 是裸字符串 / 都没有 → None。"""
    out = normalize_options(
        [
            {"text": "A", "figure_key": "square"},
            {"text": "B", "figure": "para"},
            {"text": "C"},
            {"text": "D", "figure": {"label": "没有键"}},
        ]
    )
    assert out is not None
    assert [o["figure_key"] for o in out] == ["square", "para", None, None]


def test_dict_option_with_blank_text_dropped():
    assert normalize_options([{"text": "  "}, {"text": "A. 苹果"}]) == [
        {"text": "A. 苹果", "figure_key": None}
    ]


def test_mixed_str_and_dict_elements():
    out = normalize_options(["A. 文字", {"text": "B. 带图", "figure": {"key": "square"}}])
    assert out is not None
    assert [(o["text"], o["figure_key"]) for o in out] == [
        ("A. 文字", None),
        ("B. 带图", "square"),
    ]


# ───────────────────── option_texts ─────────────────────


def test_option_texts_reads_objects():
    opts = [
        {"text": "A. 正方形", "figure_key": "square"},
        {"text": "B. 平行四边形", "figure_key": "para"},
    ]
    assert option_texts(opts) == ["A. 正方形", "B. 平行四边形"]


def test_option_texts_tolerates_legacy_strings_and_junk():
    assert option_texts(["A. 苹果", "B. 香蕉"]) == ["A. 苹果", "B. 香蕉"]
    assert option_texts(None) == []
    assert option_texts("A. 苹果") == []
