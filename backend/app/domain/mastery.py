"""知识点掌握度计算（T06，故事 F-204 / 验收 AC-203）。

口径说明（家长看板「各知识点掌握度」）：
- 基础分来自该知识点的历史作答正确率：最近 RECENT_WINDOW 次作答权重 60%，
  全部历史正确率权重 40%，得到一个 0~100 的「基础正确率分」。
- 存在活跃错题（未毕业）时，该知识点不算掌握，分数按复习进度封顶：
  cap = min(85, 60 + max_review_stage * 6)。复习答对推进阶段 → 封顶提高 → 分数上升，
  满足「复习正确后掌握度提升并反映在看板」；毕业（错题被移除）→ 解除封顶 → 可达到「已掌握」。
- 等级映射：未开始 / 待加强 / 薄弱 / 巩固中 / 较扎实 / 已掌握。
"""

RECENT_WINDOW = 10  # 「最近作答」滑动窗口大小

# 封顶参数：有活跃错题时，基础分最高只能到 84（永远够不到「已掌握」的 85 分线）
_MASTERY_CAP_FLOOR = 60.0  # stage 0（刚答错）时的封顶
_MASTERY_CAP_STEP = 6.0  # 每推进一个复习阶段，封顶提高的分数
_MASTERY_CAP_CEILING = 85.0  # 有活跃错题时的绝对上限（=「已掌握」分数线）

# 等级分数线
_LEVEL_MASTERED = 85.0  # 已掌握（无活跃错题）
_LEVEL_SOLID = 70.0  # 巩固中（有活跃错题）/ 较扎实（无活跃错题）
_LEVEL_WEAK = 50.0  # 薄弱 / 待加强

# 等级文案
LEVEL_NOT_STARTED = "未开始"
LEVEL_TO_REVIEW = "待加强"
LEVEL_WEAK = "薄弱"
LEVEL_CONSOLIDATING = "巩固中"
LEVEL_SOLID = "较扎实"
LEVEL_MASTERED = "已掌握"


def compute_mastery_score(
    *,
    total_answers: int,
    correct_answers: int,
    recent_total: int,
    recent_correct: int,
    active_wrong: int,
    max_review_stage: int,
) -> float:
    """计算某知识点的掌握度分数（0~100，1 位小数）。

    - total_answers == 0：未开始，0 分。
    - 无 recent 作答（理论上不会发生，练习即产生记录）时退化为全部历史正确率。
    - 有活跃错题时按复习进度封顶；毕业（active_wrong == 0）不封顶。
    """
    if total_answers <= 0:
        return 0.0
    accuracy = correct_answers / total_answers
    recent_accuracy = (
        recent_correct / recent_total if recent_total > 0 else accuracy
    )
    base = (0.6 * recent_accuracy + 0.4 * accuracy) * 100.0
    if active_wrong > 0:
        cap = min(
            _MASTERY_CAP_CEILING,
            _MASTERY_CAP_FLOOR + max_review_stage * _MASTERY_CAP_STEP,
        )
        return round(min(base, cap), 1)
    return round(base, 1)


def mastery_level(
    *, total_answers: int, score: float, active_wrong: int
) -> str:
    """由分数与错题状态映射掌握度等级。"""
    if total_answers <= 0:
        return LEVEL_NOT_STARTED
    if active_wrong > 0:
        # 仍有未毕业错题：最多「巩固中」，永远到不了「已掌握」
        if score >= _LEVEL_SOLID:
            return LEVEL_CONSOLIDATING
        if score >= _LEVEL_WEAK:
            return LEVEL_WEAK
        return LEVEL_TO_REVIEW
    if score >= _LEVEL_MASTERED:
        return LEVEL_MASTERED
    if score >= _LEVEL_SOLID:
        return LEVEL_SOLID
    if score >= _LEVEL_WEAK:
        return LEVEL_WEAK
    return LEVEL_TO_REVIEW
