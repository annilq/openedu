"""导出文档装配测试（次接缝：纯函数，不碰 DB / HTTP / Typst）。

为什么不在 PDF 上断言内容规则：Typst 会子集化字体，产出的 PDF 文本层 grep
不到内容；内容规则（分节 / 题号 / 降级 / 无答案）在**文档模型层**断言既更强
也更便宜。PDF 本身只断言「是份有效 PDF」，那是 HTTP 接缝的事。
"""
from dataclasses import fields, is_dataclass

from app.features.export.document import (
    ANSWER_SPACE_BLANK_LINE,
    ANSWER_SPACE_CHOICE,
    ANSWER_SPACE_WRITING_AREA,
    QuestionGroup,
    RawQuestion,
    build_export_document,
    group_by_subject,
)


def _q(stem: str, *, options: list[str] | None = None, qtype: str = "calc", subject: str = "数学") -> RawQuestion:
    return RawQuestion(stem=stem, options=options or [], qtype=qtype, subject=subject)


def _walk_field_names(node: object) -> set[str]:
    """递归收集数据类树上的全部字段名——用来证明 answer / explanation 不存在。"""
    names: set[str] = set()
    if is_dataclass(node):
        for f in fields(node):  # type: ignore[arg-type]
            names.add(f.name)
            value = getattr(node, f.name)
            if isinstance(value, (list, tuple)):
                for item in value:
                    names |= _walk_field_names(item)
            elif is_dataclass(value):
                names |= _walk_field_names(value)
    return names


def test_document_model_has_no_answer_or_explanation_anywhere():
    groups = group_by_subject(
        [
            _q("1 + 1 = ?", subject="数学"),
            _q("选项题", options=["甲", "乙"], qtype="choice", subject="语文"),
        ]
    )
    document = build_export_document(title="测试", groups=groups)
    names = _walk_field_names(document)
    assert "answer" not in names
    assert "explanation" not in names


def test_question_numbers_are_continuous_across_sections():
    groups = group_by_subject(
        [
            _q("数学一", subject="数学"),
            _q("数学二", subject="数学"),
            _q("语文一", subject="语文"),
        ]
    )
    document = build_export_document(title="测试", groups=groups)
    numbers = [q.no for section in document.sections for q in section.questions]
    assert numbers == [1, 2, 3]


def test_bank_groups_by_subject_but_single_subject_has_no_heading():
    multi = group_by_subject([_q("数", subject="数学"), _q("语", subject="语文")])
    assert [g.heading for g in multi] == ["数学", "语文"]

    single = group_by_subject([_q("数一", subject="数学"), _q("数二", subject="数学")])
    assert len(single) == 1
    assert single[0].heading is None


def test_subject_grouping_keeps_list_order():
    questions = [_q("数1", subject="数学"), _q("语1", subject="语文"), _q("数2", subject="数学")]
    groups = group_by_subject(questions)
    assert [q.stem for q in groups[0].questions] == ["数1", "数2"]
    assert [q.stem for q in groups[1].questions] == ["语1"]


def test_markdown_and_tex_are_stripped_and_counted():
    document = build_export_document(
        title="测试",
        groups=[
            QuestionGroup(
                heading=None,
                subject="数学",
                questions=(
                    _q("$\\frac{1}{2} + \\frac{1}{2}$ = ?"),
                    _q("看图回答 ![示意图](http://x/y.png)"),
                    _q("纯文本题"),
                ),
            )
        ],
    )
    questions = document.sections[0].questions
    assert questions[0].stem == "\\frac{1}{2} + \\frac{1}{2} = ?"
    assert questions[1].stem == "看图回答 示意图"
    assert questions[2].stem == "纯文本题"
    assert document.downgraded == 2


def test_duplicate_option_prefix_is_removed():
    document = build_export_document(
        title="测试",
        groups=[
            QuestionGroup(
                heading=None,
                subject="数学",
                questions=(
                    _q("选一选", options=["A. 第一个", "B、第二个", "（C）第三个"], qtype="choice"),
                ),
            )
        ],
    )
    assert document.sections[0].questions[0].options == ("第一个", "第二个", "第三个")


def test_answer_space_follows_options_not_qtype_name():
    document = build_export_document(
        title="测试",
        groups=[
            QuestionGroup(
                heading=None,
                subject="数学",
                questions=(
                    # qtype 叫 fill 但给了选项 → 有选项即走选项（沿用屏幕上的二分法）
                    _q("假填空", options=["甲"], qtype="fill"),
                    _q("真填空", qtype="fill"),
                    _q("计算题", qtype="calc"),
                    _q("应用题", qtype="open"),
                ),
            )
        ],
    )
    spaces = [q.answer_space for q in document.sections[0].questions]
    assert spaces == [
        ANSWER_SPACE_CHOICE,
        ANSWER_SPACE_BLANK_LINE,
        ANSWER_SPACE_WRITING_AREA,
        ANSWER_SPACE_WRITING_AREA,
    ]


def test_empty_options_entries_are_dropped():
    document = build_export_document(
        title="测试",
        groups=[
            QuestionGroup(
                heading=None,
                subject="数学",
                questions=(_q("选一选", options=["", "  ", "有效项"], qtype="choice"),),
            )
        ],
    )
    assert document.sections[0].questions[0].options == ("有效项",)


def test_strip_rich_text_keeps_fill_blanks():
    """填空的下划线不能被当成 Markdown 强调剥掉。

    题干里 `____` 就是「孩子要在这里写字」，剥掉它等于把纸上的空抹了——
    孩子看着一句话却不知道往哪填。判据：强调必须**紧贴文字**，被空格孤立的
    一串下划线是留白，不是强调。
    """
    from app.features.export.document import strip_rich_text

    for stem in (
        "请把 ________ 补充完整",
        "I ___ a student.",
        "描写春天的四字词语：____、____",
    ):
        plain, degraded = strip_rich_text(stem)
        assert plain == stem, stem
        assert degraded is False


def test_strip_rich_text_removes_emphasis_but_keeps_content():
    """剥的是**定界符**，被包裹的文字要留下。"""
    from app.features.export.document import strip_rich_text

    plain, degraded = strip_rich_text("甲数是 __8__，乙数是 __5__")
    assert plain == "甲数是 8，乙数是 5"
    assert degraded is False

    plain, degraded = strip_rich_text("计算 **1/2** 的和")
    assert plain == "计算 1/2 的和"
    assert degraded is False


def test_strip_rich_text_flags_formula_and_image():
    from app.features.export.document import strip_rich_text

    plain, degraded = strip_rich_text("求 $x^2$ 的值")
    assert plain == "求 x^2 的值"
    assert degraded is True

    plain, degraded = strip_rich_text("![示意图](http://x/y.png) 看图作答")
    assert plain == "示意图 看图作答"
    assert degraded is True
