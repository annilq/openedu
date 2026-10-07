"""Analytics feature request/response schemas (teacher-scale-up ticket 11)。

三态作用域（student / class / all）× 四维分组（subject / grade / semester /
knowledge_point）的学情统计聚合端点，数据全部源于作答记录与错题 JOIN 题目，无需新表。
口径见 ADR-0070「四项必须钉死的口径」。
"""

from sqlmodel import SQLModel

# ───────────────────────── 错题分布（wrong-distribution） ─────────────────────────


class WrongDistributionGroup(SQLModel):
    """单个维度分组的错题计数：活跃（未毕业）与已毕业分开。"""

    group: str
    active: int
    graduated: int
    total: int


class WrongDistributionResp(SQLModel):
    """错题分布聚合结果。

    - ``orphan_count``：孤儿错题（原题已被硬删，JOIN 不到）数量，显式标注、不混入任何分组。
    - 空学期统一收敛为「整学年」，不产生空白分组。
    """

    scope: str
    dimension: str
    total_active: int
    total_graduated: int
    total: int
    groups: list[WrongDistributionGroup] = []
    orphan_count: int = 0


# ───────────────────────── 正确率（accuracy） ─────────────────────────


class AccuracySourceBreakdown(SQLModel):
    total: int = 0
    correct: int = 0
    accuracy: float = 0.0


class AccuracyGroup(SQLModel):
    """单个维度分组的练习/复习正确率。"""

    group: str
    practice: AccuracySourceBreakdown = AccuracySourceBreakdown()
    review: AccuracySourceBreakdown = AccuracySourceBreakdown()
    overall: AccuracySourceBreakdown = AccuracySourceBreakdown()


class AccuracyResp(SQLModel):
    scope: str
    dimension: str
    source: str
    groups: list[AccuracyGroup] = []
    orphan_count: int = 0


# ───────────────────────── 掌握度（mastery） ─────────────────────────


class MasteryGroup(SQLModel):
    """单个知识点的批量掌握度（跨作用域内所有学生聚合）。

    active_wrong / max_review_stage 只数活跃（未毕业）错题；score/level 复用
    ``app.domain.mastery`` 的纯函数，保证与单学生看板口径一致。
    """

    knowledge_point: str
    subject: str
    grade: int
    total_answers: int = 0
    correct_answers: int = 0
    accuracy: float = 0.0
    active_wrong: int = 0
    max_review_stage: int = 0
    score: float = 0.0
    level: str = ""


class MasteryResp(SQLModel):
    scope: str
    total_knowledge_points: int = 0
    mastered_count: int = 0
    items: list[MasteryGroup] = []
    orphan_count: int = 0
