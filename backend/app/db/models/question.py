import uuid
from datetime import datetime

from sqlalchemy import JSON, DateTime, Index
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc

# 题目来源（ADR-0060）：区分 AI 生成与家长度录，是版权门禁（ADR-0020）判定
# 「仿写是否放大侵权风险」的前提——仿写只应作用于 AI 生成题，不会把家长从
# 教辅录入的题再繁衍成 N 道。存量行经 run_migrations 回填为 "ai"。
QUESTION_ORIGIN_AI = "ai"
QUESTION_ORIGIN_PARENT = "parent"


class Question(SQLModel, table=True):
    """题库层（ADR-0004 D2）：Question 表本身即题库，删 task_id 独立实体，可跨 Task 复用。

    parent_id（题库复用闭环）：归属家长，实现 owner 隔离，避免多家庭互通题库。
    旧库通过 db.run_migrations 回填（见 backend/app/core/db.py）。
    """

    # 列表游标分页按 (parent_id, created_at 倒序) 取页（ADR-0053）。
    __table_args__ = (Index("ix_question_parent_created", "parent_id", "created_at"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")  # 题库 owner 隔离（闭环）
    origin: str = Field(default=QUESTION_ORIGIN_AI, max_length=16)
    subject: str
    grade: int
    knowledge_point: str
    # 学期维度（ADR-0061 发布任务对接资料库）：'' = 不限/整学年；'上学期' / '下学期'。
    # 与知识点唯一约束 (parent_id, subject, grade, name, semester) 对齐，便于按学期
    # 精确关联家长私有知识点模板，进而在讲解时按知识点预设场景演示。
    semester: str = Field(default="", max_length=8)
    qtype: str
    stem: str
    options: list[str] | None = Field(default=None, sa_type=JSON)
    answer: str | None = None
    explanation: str | None = None
    difficulty: str | None = None
    # 资料溯源快照（ADR-0055 §10）：[{material: 资料名, snippet: 片段摘要}]。
    # 刻意不建 source_chunk_ids 外键——家长删资料后题目不失去依据，也无删除级联。
    source_refs: list[dict] | None = Field(default=None, sa_type=JSON)
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    # 显式归档（ADR-0053 P2）：None = 在用。
    #
    # 为什么不是「删除」：被任务引用的题删不掉，家长于是「不敢删、只能堆着」——
    # 题库只增不减的根因就是这个心理。归档必须可恢复，所以它只是一个可空时间戳，
    # 而不是布尔 + 不可逆删除。
    archived_at: datetime | None = Field(
        default=None,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    # 本题的交互式讲解实例（ADR-0061）：出题时从对应知识点 scenes 取模板、覆盖本题
    # 数值得到。学生端可在题卡解析区/讲解卡内联渲染，并继续改 inputs 求解。刻意不建
    # 外键（快照式）：知识点模板改动不影响已生成的题。可空 = 本题不可图形化。
    scene_spec: dict | None = Field(default=None, sa_type=JSON)
