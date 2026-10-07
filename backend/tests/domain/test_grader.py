"""Grader 评分回归：客观题归一化比对 + 多选题集合比对（ADR-0004 D5）。"""

from app.domain.grader import Grader


class _FakeQuestion:
    """最小化的题目对象：grader 只读取 qtype / answer / multi / explanation。"""

    def __init__(self, qtype: str, answer: str, multi: bool = False, subject: str | None = None) -> None:
        self.qtype = qtype
        self.answer = answer
        self.multi = multi
        self.subject = subject
        self.explanation = ""


def test_single_choice_exact_match():
    q = _FakeQuestion("choice", "苹果")
    assert Grader(None).grade(question=q, student_answer="苹果")["correct"] is True
    assert Grader(None).grade(question=q, student_answer="香蕉")["correct"] is False


def test_single_choice_whitespace_insensitive():
    q = _FakeQuestion("choice", " 苹果 ")
    # 归一化忽略空白与大小写。
    assert Grader(None).grade(question=q, student_answer="苹果")["correct"] is True
    assert Grader(None).grade(question=q, student_answer="APPLE")["correct"] is False


def test_multi_choice_set_match_order_independent():
    # answer 与作答均为「｜」连接的选项文本；顺序/重复不计（ADR-0004 D5）。
    q = _FakeQuestion("choice", "苹果|香蕉", multi=True)
    assert (
        Grader(None).grade(question=q, student_answer="香蕉|苹果")["correct"] is True
    )
    assert (
        Grader(None).grade(question=q, student_answer="苹果|香蕉|苹果")["correct"] is True
    )


def test_multi_choice_partial_wrong():
    q = _FakeQuestion("choice", "苹果|香蕉", multi=True)
    # 少选 / 多选 / 错选都应判错。
    assert Grader(None).grade(question=q, student_answer="苹果")["correct"] is False
    assert Grader(None).grade(question=q, student_answer="苹果|香蕉|橙子")["correct"] is False
    assert Grader(None).grade(question=q, student_answer="橙子")["correct"] is False


def test_multi_choice_accepts_list_payload():
    # 前端多选取集也可能直接以 list 形式回传，grader 应等价于「｜」连接串。
    q = _FakeQuestion("choice", "苹果|香蕉", multi=True)
    assert (
        Grader(None).grade(question=q, student_answer=["香蕉", "苹果"])["correct"] is True
    )


# ── ADR-0071：数学客观题数值等价（ticket 02）───────────────────────────
def test_math_fill_unit_bare_equiv():
    # 数学填空：带单位作答 与 纯数值标准答案 系数匹配即判等。
    q = _FakeQuestion("fill", "12", subject="数学")
    assert Grader(None).grade(question=q, student_answer="12厘米")["correct"] is True
    # 同量纲不同单位经基准换算等价。
    assert (
        Grader(None).grade(
            question=_FakeQuestion("fill", "12厘米", subject="数学"),
            student_answer="0.12米",
        )["correct"]
        is True
    )
    # 数值不等仍错（回退严格相等也错）。
    assert Grader(None).grade(question=q, student_answer="13厘米")["correct"] is False


def test_math_fill_fraction_decimal_equiv():
    # 分数与小数互转、约分均判等。
    q = _FakeQuestion("fill", "0.5", subject="数学")
    assert Grader(None).grade(question=q, student_answer="1/2")["correct"] is True
    assert Grader(None).grade(question=q, student_answer="2/4")["correct"] is True


def test_math_calc_mixed_fraction_equiv():
    # 数学计算：带分数与小数判等。
    q = _FakeQuestion("calc", "3.5", subject="数学")
    assert Grader(None).grade(question=q, student_answer="3又1/2")["correct"] is True


def test_math_fill_neutral_classifier_equiv():
    # 中性量词（个）视为无量纲，仅比系数。
    q = _FakeQuestion("fill", "5", subject="数学")
    assert Grader(None).grade(question=q, student_answer="5个")["correct"] is True


def test_math_fill_dimension_incompatible():
    # 量纲不兼容（长度 vs 质量）判错。
    q = _FakeQuestion("fill", "5cm", subject="数学")
    assert Grader(None).grade(question=q, student_answer="5kg")["correct"] is False


def test_math_fill_parse_failure_falls_back_to_strict():
    # 含等式/符号等非数值文本 → 解析失败 → 回退严格相等（与改造前行为一致）。
    q = _FakeQuestion("fill", "5", subject="数学")
    assert Grader(None).grade(question=q, student_answer="x=5")["correct"] is False


def test_non_math_fill_stays_strict():
    # 不变量：非数学填空不走数值等价，仍严格相等（避免误伤词/短语答案）。
    q = _FakeQuestion("fill", "苹果", subject="语文")
    assert Grader(None).grade(question=q, student_answer="苹果")["correct"] is True
    assert Grader(None).grade(question=q, student_answer="梨")["correct"] is False


def test_math_objective_invariants_unchanged():
    # 不变量：改造前 choice(非数学) / multi 判定结果不变。
    q_choice = _FakeQuestion("choice", "苹果")
    assert Grader(None).grade(question=q_choice, student_answer="苹果")["correct"] is True
    q_multi = _FakeQuestion("choice", "苹果|香蕉", multi=True)
    assert Grader(None).grade(question=q_multi, student_answer="苹果")["correct"] is False

