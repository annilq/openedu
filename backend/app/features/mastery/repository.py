"""Repository layer for the mastery feature (knowledge-point aggregation)."""

import uuid
from dataclasses import dataclass, field

from sqlmodel import Session, select

from app.db.models import AnswerRecord, Question, WrongQuestion
from app.domain.mastery import RECENT_WINDOW

# 每个知识点随掌握度返回的代表错题上限（ADR-0060 D4：服务端挑、随看板下发，
# 前端据此走「就这个知识点出题」的同类题仿写）。取 3 是「足够覆盖主流坑、又不
# 让看板响应与 prompt 膨胀」的折中。
REPRESENTATIVE_WRONG_LIMIT = 3


@dataclass
class KnowledgePointAgg:
    """单个知识点的掌握度原始聚合（喂给 domain/mastery 纯函数）。"""

    knowledge_point: str
    subject: str
    grade: int
    total_answers: int = 0
    correct_answers: int = 0
    recent_total: int = 0
    recent_correct: int = 0
    active_wrong: int = 0
    max_review_stage: int = 0
    # 代表错题（Question.id 字符串）：错误次数最高、且未毕业的题，最多
    # REPRESENTATIVE_WRONG_LIMIT 条，供「同类题仿写」出口使用（ADR-0060）。
    representative_wrong_ids: list[str] = field(default_factory=list)


def get_knowledge_point_mastery(
    *, session: Session, child_id: uuid.UUID
) -> list[KnowledgePointAgg]:
    """聚合某娃娃的按知识点掌握度输入数据。

    - 作答记录按 created_at 倒序取最近 RECENT_WINDOW 次作为「近期表现」。
    - 活跃错题（未毕业）计入 active_wrong 与最高复习阶段 max_review_stage。
    """
    groups: dict[str, KnowledgePointAgg] = {}

    records = session.exec(
        select(AnswerRecord, Question)
        .join(Question, Question.id == AnswerRecord.question_id)
        .where(AnswerRecord.child_id == child_id)
        .order_by(AnswerRecord.created_at.desc(), AnswerRecord.id.desc())
    ).all()
    for rec, q in records:
        agg = groups.get(q.knowledge_point)
        if agg is None:
            agg = KnowledgePointAgg(
                knowledge_point=q.knowledge_point,
                subject=q.subject,
                grade=q.grade,
            )
            groups[q.knowledge_point] = agg
        agg.total_answers += 1
        agg.correct_answers += 1 if rec.correct else 0
        if agg.recent_total < RECENT_WINDOW:
            agg.recent_total += 1
            agg.recent_correct += 1 if rec.correct else 0

    wrong_rows = session.exec(
        select(WrongQuestion, Question)
        .join(Question, Question.id == WrongQuestion.question_id)
        .where(
            WrongQuestion.child_id == child_id,
            # 已毕业（已掌握）的错题不算「活跃」（ADR-0053 P2 起毕业不删行，
            # 这里必须显式排除，否则掌握度会被一条已经掌握的错题永久封顶）。
            WrongQuestion.graduated_at.is_(None),  # type: ignore[union-attr]
        )
        # 错误次数高的题更具「代表坑」意义，优先入选（同分按最早错出时间稳定排序）。
        .order_by(WrongQuestion.wrong_count.desc(), WrongQuestion.first_wrong_at.desc())
    ).all()
    for wq, q in wrong_rows:
        agg = groups.get(q.knowledge_point)
        if agg is not None:  # 答错必写过作答记录，理论恒存在
            agg.active_wrong += 1
            agg.max_review_stage = max(agg.max_review_stage, wq.review_stage)
            # 代表错题：每个知识点最多取 REPRESENTATIVE_WRONG_LIMIT 条。
            if len(agg.representative_wrong_ids) < REPRESENTATIVE_WRONG_LIMIT:
                agg.representative_wrong_ids.append(str(q.id))

    return list(groups.values())
