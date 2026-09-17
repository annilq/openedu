"""导出文档（ADR-0052 · CONTEXT.md §打印导出）。

这是服务端排版链路的**中间数据契约**：一次打印导出 = 标题 + 若干打印分节，
每节一组题目的纯文本快照。它往下交给 Typst 模板，往上由四个来源（题库 / 任务 /
错题本 / 复习）各自装配。

**这里刻意不设 ``answer`` / ``explanation`` 字段。** 学生卷不带答案是硬约束，
最可靠的保证不是「渲染时过滤掉」，而是「契约里从来没有这两个字段」——
类型系统直接拒绝了它们，任何把答案读进导出文档的改动都无处安放。

同理，题号在**装配阶段**就算好（跨节连续），模板只负责把它画出来。
"""
from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass

# ── 学科三重编码的形状层（ADR-0044）────────────────────────
# 屏幕上是 CustomPaint 画的几何图形，纸上是字符。同一个形状的两种介质，
# 关键是「黑白打印也成立」——这正是 shape 层存在的理由。
SUBJECT_MARKS: dict[str, str] = {
    "数学": "■",
    "语文": "●",
    "英语": "▲",
}

# 作答留白形态。只表达「这道题要孩子做什么」，具体毫米数在模板里——
# 那是版式决策，不是数据。
ANSWER_SPACE_CHOICE = "choice"  # 有选项：选项本身即作答区，题后留少量间隔
ANSWER_SPACE_BLANK_LINE = "blank_line"  # 填空：一条横线
ANSWER_SPACE_WRITING_AREA = "writing_area"  # 计算 / 应用：一块空白答题区

# 图片语法 ![alt](url)：有 alt 留 alt，纯图无 alt 则整句去掉（不能留 URL 在纸上）
_IMAGE = re.compile(r"!\[([^\]]*)\]\([^)]*\)")
_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
# 星号与反引号：题干里不会拿它们当填空，直接剥。
_EMPHASIS_STAR = re.compile(r"[*`]{1,3}")
# 下划线必须**成对且紧贴文字**才当强调：填空题干是靠一串下划线表示「这里要写」
# （如 "I ___ a student."），一律剥掉等于把纸上的空抹了，孩子没地方下笔。
# 键党组：Markdown 强调要求标记紧贴内容，被空格孤立的长横线不是强调。
_EMPHASIS_UNDERSCORE = re.compile(r"(?<![\w])_{1,3}(?=[^\s_])([^\n]*?)_{1,3}(?![_\w])")
_TEX_DELIM = re.compile(r"\$+")
# 选项自带的字母前缀："A. " / "A、" / "（A）" / "A．"
# 库里存在自带前缀的题（测试桩就是 "A. 第一个选项"），屏幕上的字母是 UI 层生成的，
# 纸面排版必须去重，否则纸上会出现 "A. A. 第一个选项"。
_OPTION_PREFIX = re.compile(r"^[\(（\[]?[A-Za-z][\)）\].、：:．]\s*")


@dataclass(frozen=True)
class RawQuestion:
    """参与排版的题：由 repository 从 ORM 行映射而来，尚未做纯文本降级。"""

    stem: str
    options: Sequence[str]
    qtype: str
    subject: str = ""


@dataclass(frozen=True)
class QuestionGroup:
    """一个打印分节的输入：节标题（None = 不分节）+ 该组的题。"""

    heading: str | None
    subject: str | None
    questions: tuple[RawQuestion, ...]


@dataclass(frozen=True)
class ExportQuestion:
    no: int
    qtype: str
    stem: str
    options: tuple[str, ...]
    answer_space: str


@dataclass(frozen=True)
class ExportSection:
    heading: str | None
    subject_mark: str | None
    questions: tuple[ExportQuestion, ...]


@dataclass(frozen=True)
class ExportDocument:
    title: str
    sections: tuple[ExportSection, ...]
    downgraded: int  # 含公式或图片、已按纯文本打印的题数


def strip_rich_text(text: str) -> tuple[str, bool]:
    """把可能含 Markdown / ``$...$`` 的题干降级为纯文本。

    返回 ``(纯文本, 是否发生过降级)``。本轮纸面不支持公式与图片渲染（见 ADR-0052
    「题干富文本」决策）：剥掉定界符与标记、保留内部的可读文本（``1/2``、``x^2``），比印出一堆
    ``\\frac{1}{2}`` 原始字符体面。降级必须由调用方如实告知用户，不能静默。
    """
    raw = text or ""
    picture = _IMAGE.search(raw) is not None
    formula = "$" in raw
    plain = _IMAGE.sub(lambda m: m.group(1).strip(), raw)
    plain = _LINK.sub(r"\1", plain)
    plain = _EMPHASIS_STAR.sub("", plain)
    # 只剥定界符、保留被包裹的文字（`.sub(r"\1")`），不是把整段吃掉。
    plain = _EMPHASIS_UNDERSCORE.sub(r"\1", plain)
    plain = _TEX_DELIM.sub("", plain)
    return plain.strip(), picture or formula


def strip_option_prefix(option: str) -> str:
    """去掉选项自带的字母前缀——纸面上的字母由模板统一生成。"""
    return _OPTION_PREFIX.sub("", (option or "").strip())


def answer_space_for(*, qtype: str, options: Sequence[str]) -> str:
    """按题型推导作答留白。

    判据沿用既有约定：**有选项即走选项**（options 非空），否则按 qtype 给留白。
    不看 qtype 名字硬猜有没有选项——屏幕上也是这个二分法。
    """
    if options:
        return ANSWER_SPACE_CHOICE
    if qtype == "fill":
        return ANSWER_SPACE_BLANK_LINE
    return ANSWER_SPACE_WRITING_AREA


def subject_mark(subject: str | None) -> str | None:
    return SUBJECT_MARKS.get(subject or "")


def _to_export_question(no: int, raw: RawQuestion) -> tuple[ExportQuestion, bool]:
    stem, stem_downgraded = strip_rich_text(raw.stem)
    options: list[str] = []
    options_downgraded = False
    for option in raw.options or ():
        text = strip_option_prefix(str(option))
        if not text:
            continue
        text, degraded = strip_rich_text(text)
        options_downgraded = options_downgraded or degraded
        options.append(text)
    return (
        ExportQuestion(
            no=no,
            qtype=raw.qtype,
            stem=stem,
            options=tuple(options),
            answer_space=answer_space_for(qtype=raw.qtype, options=options),
        ),
        stem_downgraded or options_downgraded,
    )


def build_export_document(*, title: str, groups: Sequence[QuestionGroup]) -> ExportDocument:
    """把分组好的题装配成导出文档：定题号、做纯文本降级、附学科标记。

    题号**跨节连续**——娃娃用批改 App 扫码时，纸面上不能出现两个「第 1 题」。
    """
    sections: list[ExportSection] = []
    downgraded = 0
    no = 0
    for group in groups:
        items: list[ExportQuestion] = []
        for raw in group.questions:
            no += 1
            question, degraded = _to_export_question(no, raw)
            if degraded:
                downgraded += 1
            items.append(question)
        sections.append(
            ExportSection(
                heading=group.heading,
                subject_mark=subject_mark(group.subject),
                questions=tuple(items),
            )
        )
    return ExportDocument(title=title, sections=tuple(sections), downgraded=downgraded)


def group_by_subject(questions: Sequence[RawQuestion]) -> list[QuestionGroup]:
    """题库来源的分节：按学科分组，**只有一个学科时不分节**。

    保持原题序：先用 defaultdict 保序收集（同一学科的题聚到一起），
    避免为了分组把列表顺序重排——「节内顺序 = 列表当前顺序」是明确的取舍。
    """
    buckets: dict[str, list[RawQuestion]] = {}
    order: list[str] = []
    for question in questions:
        key = question.subject or ""
        if key not in buckets:
            buckets[key] = []
            order.append(key)
        buckets[key].append(question)

    if len(order) <= 1:
        return [
            QuestionGroup(
                heading=None,
                subject=order[0] if order else None,
                questions=tuple(questions),
            )
        ]
    return [
        QuestionGroup(heading=key or "其他", subject=key, questions=tuple(buckets[key]))
        for key in order
    ]


def count_questions(document: ExportDocument) -> int:
    return sum(len(section.questions) for section in document.sections)
