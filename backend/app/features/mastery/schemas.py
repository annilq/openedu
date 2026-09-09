"""Pydantic schemas for the mastery feature."""


from sqlmodel import SQLModel


class KnowledgeMasteryResp(SQLModel):
    """单个知识点的掌握度（家长看板，F-204）。"""

    knowledge_point: str
    subject: str
    grade: int
    total_answers: int
    correct_answers: int
    accuracy: float
    active_wrong: int
    max_review_stage: int
    score: float
    level: str


class MasteryResp(SQLModel):
    """知识点掌握度看板（家长端）。"""

    child_id: object  # uuid.UUID
    total_knowledge_points: int
    mastered_count: int
    items: list[KnowledgeMasteryResp] = []
