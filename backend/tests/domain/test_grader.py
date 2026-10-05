"""Grader 评分回归：客观题归一化比对 + 多选题集合比对（ADR-0004 D5）。"""

from app.domain.grader import Grader


class _FakeQuestion:
    """最小化的题目对象：grader 只读取 qtype / answer / multi / explanation。"""

    def __init__(self, qtype: str, answer: str, multi: bool = False) -> None:
        self.qtype = qtype
        self.answer = answer
        self.multi = multi
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
