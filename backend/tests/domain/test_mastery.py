"""掌握度计算纯函数单测（T06，F-204 / AC-203）。

覆盖：未开始、全对已掌握、活跃错题封顶、复习推进提升、毕业解封、全错薄弱、
最近窗口缺失时退化到全部历史正确率。
"""
from app.domain.mastery import (
    LEVEL_CONSOLIDATING,
    LEVEL_MASTERED,
    LEVEL_NOT_STARTED,
    LEVEL_SOLID,
    LEVEL_TO_REVIEW,
    LEVEL_WEAK,
    compute_mastery_score,
    mastery_level,
)


def _score(**kw) -> float:
    return compute_mastery_score(
        total_answers=kw.get("total_answers", 0),
        correct_answers=kw.get("correct_answers", 0),
        recent_total=kw.get("recent_total", 0),
        recent_correct=kw.get("recent_correct", 0),
        active_wrong=kw.get("active_wrong", 0),
        max_review_stage=kw.get("max_review_stage", 0),
    )


def test_not_started():
    """没有任何作答记录：0 分，未开始。"""
    assert _score() == 0.0
    assert mastery_level(total_answers=0, score=0.0, active_wrong=0) == LEVEL_NOT_STARTED


def test_all_correct_no_wrong_is_mastered():
    """全部答对且无活跃错题：高分，已掌握。"""
    score = _score(total_answers=10, correct_answers=10, recent_total=10, recent_correct=10)
    assert score == 100.0
    assert mastery_level(total_answers=10, score=score, active_wrong=0) == LEVEL_MASTERED


def test_active_wrong_caps_score():
    """正确率高但有活跃错题：被复习进度封顶，stage0 只有 60 分（薄弱）。"""
    score = _score(
        total_answers=10,
        correct_answers=9,
        recent_total=10,
        recent_correct=9,
        active_wrong=1,
        max_review_stage=0,
    )
    assert score == 60.0
    assert mastery_level(total_answers=10, score=score, active_wrong=1) == LEVEL_WEAK


def test_review_progress_raises_cap():
    """AC-203 前半：复习答对推进阶段 → 封顶提高 → 分数上升。"""
    kw = dict(
        total_answers=10,
        correct_answers=9,
        recent_total=10,
        recent_correct=9,
        active_wrong=1,
    )
    caps = [_score(max_review_stage=s, **kw) for s in range(5)]
    assert caps == [60.0, 66.0, 72.0, 78.0, 84.0]
    assert all(caps[i] < caps[i + 1] for i in range(4))  # 严格递增
    # 即使复习到 15 天档（stage4），有活跃错题也到不了「已掌握」
    assert caps[-1] < 85.0
    assert mastery_level(total_answers=10, score=caps[-1], active_wrong=1) == LEVEL_CONSOLIDATING


def test_graduate_unlocks_mastery():
    """AC-203 后半：毕业（错题移除）→ 解除封顶 → 达到已掌握。"""
    kw = dict(
        total_answers=10,
        correct_answers=9,
        recent_total=10,
        recent_correct=9,
    )
    base = _score(active_wrong=0, **kw)
    assert base == 90.0  # 基础正确率分不受封顶影响
    assert mastery_level(total_answers=10, score=base, active_wrong=0) == LEVEL_MASTERED


def test_all_wrong_is_to_review():
    """全错且无复习记录：低分，待加强。"""
    score = _score(total_answers=3, correct_answers=0, recent_total=3, recent_correct=0)
    assert score == 0.0
    assert mastery_level(total_answers=3, score=score, active_wrong=1) == LEVEL_TO_REVIEW


def test_recent_missing_falls_back_to_accuracy():
    """最近窗口无数据（理论不发生）时退化为全部历史正确率。"""
    score = _score(total_answers=5, correct_answers=5, recent_total=0, recent_correct=0)
    assert score == 100.0


def test_level_edges():
    """等级分数边界。"""
    # 无活跃错题：85 已掌握、70 较扎实、50 薄弱、<50 待加强
    assert mastery_level(total_answers=1, score=85.0, active_wrong=0) == LEVEL_MASTERED
    assert mastery_level(total_answers=1, score=84.9, active_wrong=0) == LEVEL_SOLID
    assert mastery_level(total_answers=1, score=70.0, active_wrong=0) == LEVEL_SOLID
    assert mastery_level(total_answers=1, score=69.9, active_wrong=0) == LEVEL_WEAK
    assert mastery_level(total_answers=1, score=50.0, active_wrong=0) == LEVEL_WEAK
    assert mastery_level(total_answers=1, score=49.9, active_wrong=0) == LEVEL_TO_REVIEW
    # 有活跃错题：最高只能「巩固中」
    assert mastery_level(total_answers=1, score=99.0, active_wrong=1) == LEVEL_CONSOLIDATING
