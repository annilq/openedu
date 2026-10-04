"""资料库四表（ADR-0055）：家长上传资料 → 元数据提取 → 切片向量化 → RAG 出题。

命名红线（CONTEXT.md §资料库与检索）：**不叫 Resource**（前端 `Resource<T>` 是
加载态三态包装器，撞名）**也不叫素材**（题库已是「出题素材池」）。

归属纪律：四张表全部带 ``parent_id``，越权校验直接复用 ``core.guard``——
不新增任何鉴权路径（ADR-0055 §1）。

迁移纪律：全新表，``init_db`` 的 ``create_all`` 自动建表，无需启动期 ALTER；
索引随表定义走（ADR-0053 纪律：不引入 alembic）。
"""

import uuid
from datetime import datetime

from sqlalchemy import JSON, Column, DateTime, Index, LargeBinary, UniqueConstraint
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc

# ── 资料向量化状态机（ADR-0055 §5）───────────────────────────────────────
# pending = 已上传未向量化；ready = 向量可用；failed = 上次向量化失败；
# stale  = embedding 模型或切分策略已变更，存量向量语义失效，待重算。
INDEX_STATE_PENDING = "pending"
INDEX_STATE_READY = "ready"
INDEX_STATE_FAILED = "failed"
INDEX_STATE_STALE = "stale"
INDEX_STATES: tuple[str, ...] = (
    INDEX_STATE_PENDING,
    INDEX_STATE_READY,
    INDEX_STATE_FAILED,
    INDEX_STATE_STALE,
)

# ── 知识点目录状态（ADR-0055 §4）─────────────────────────────────────────
# pending（待审）：可用于出题与检索，但**不计入掌握度分组**；
# curated（转正）：家长确认后参与掌握度统计。
KP_STATUS_PENDING = "pending"
KP_STATUS_CURATED = "curated"

# 骨架兜底来源标记：emerged = 资料解析涌现；skeleton = 自编骨架落库（冷启动）。
# 骨架优先在 service 层与 DB 行合并展示，只有家长确认骨架条目时才落库。
KP_SOURCE_EMERGED = "emerged"
KP_SOURCE_SKELETON = "skeleton"

# 切片器版本戳（ADR-0055 §5）：改切分策略时递增，变更后存量 chunk 标 stale。
CHUNKER_VERSION = "v1"


class MaterialFolder(SQLModel, table=True):
    """资料目录（网盘式，ADR-0055 §2）。

    目录可设学科 + 年级，其下子目录与资料**继承**，单份资料可覆盖；
    **不绑 child**（多娃共用一份资料库）。目录只负责组织与提供元数据，
    检索范围永远按家长归属隔离，不按目录。
    """

    __table_args__ = (Index("ix_materialfolder_parent", "parent_id"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")
    name: str = Field(max_length=128)
    # 继承元数据：None = 未设置（上传/解析时逐级向上找最近祖先补齐）
    subject: str | None = Field(default=None, max_length=16)
    grade: int | None = None
    # 学期范围维度（ADR-0055 §2 补）：'' / '上学期' / '下学期'；None = 未设置（继承）。
    semester: str | None = Field(default=None, max_length=8)
    parent_folder_id: uuid.UUID | None = Field(
        default=None, foreign_key="materialfolder.id"
    )
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class Material(SQLModel, table=True):
    """一份上传资料 = 一个文件（ADR-0055 §1）。

    切分出的 chunk 是内部实现，不暴露给用户。``text`` 存解析出的整篇纯文本
    （元数据整篇提取的数据源）；删除资料时片段与向量一并删除（快照溯源
    不受影响——题目只存资料名 + 片段摘要，见 ADR-0055 §10）。
    """

    __table_args__ = (Index("ix_material_parent_folder", "parent_id", "folder_id"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")
    folder_id: uuid.UUID | None = Field(default=None, foreign_key="materialfolder.id")
    name: str = Field(max_length=255)  # 展示名（原始文件名）
    storage_key: str = Field(max_length=512)  # 落盘相对路径（挂 upload_root 下）
    mime: str = Field(default="", max_length=128)
    size_bytes: int = Field(default=0)
    # 解析出的整篇纯文本（pypdf / python-docx / 原文直读）
    text: str | None = None
    # 整篇提取的元数据（AI 读全文一次，广播给所有 chunk——不逐 chunk 提取）
    subject: str | None = Field(default=None, max_length=16)
    grade: int | None = None
    # 学期（继承目录，ADR-0055 §2 补）：None = 未设置。
    semester: str | None = Field(default=None, max_length=8)
    knowledge_points: list[str] | None = Field(default=None, sa_type=JSON)
    # 向量化状态机 + 版本戳（ADR-0055 §5）：向量绑定模型，换模型/切分器即 stale
    index_state: str = Field(default=INDEX_STATE_PENDING, max_length=16)
    embed_model: str | None = Field(default=None, max_length=128)
    chunker_ver: str | None = Field(default=None, max_length=16)
    index_error: str | None = None  # failed 时的人话原因
    indexed_at: datetime | None = Field(
        default=None,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class MaterialChunk(SQLModel, table=True):
    """资料片段：检索的最小单元（ADR-0055 §6）。

    向量存 ``embedding``（二进制，服务内暴力扫余弦——单家长数千向量毫秒级，
    不引入 pgvector / 向量库）。片段继承整篇元数据；``embed_model`` 与
    ``chunker_ver`` 落到 chunk 上，检索时跳过版本不匹配的行（双保险，
    Material 上的状态机是给用户看的口径）。
    """

    __table_args__ = (
        Index("ix_materialchunk_material", "material_id", "seq"),
        Index("ix_materialchunk_filter", "parent_id", "subject", "grade"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")
    material_id: uuid.UUID = Field(foreign_key="material.id")
    seq: int  # 片段在资料内的顺序
    content: str
    knowledge_point: str | None = Field(
        default=None, max_length=128
    )  # 命中片段归属知识点（就近匹配）
    embedding: bytes | None = Field(
        default=None, sa_column=Column("embedding", LargeBinary)
    )
    embed_model: str | None = Field(default=None, max_length=128)
    chunker_ver: str | None = Field(default=None, max_length=16)
    # 冗余自 Material（整篇提取广播）：检索过滤键，免 join
    subject: str = Field(max_length=16)
    grade: int


class KnowledgePoint(SQLModel, table=True):
    """受控知识点目录（ADR-0055 §4）：涌现优先 + 自编骨架兜底。

    唯一约束 ``(parent_id, subject, grade, name)``——知识点是**家长私有的**
    （从他家资料涌现的目录对自家没意义），不建全局表。待审条目可用于出题
    与检索，但**不计入掌握度分组**，转正后才参与统计。
    """

    __table_args__ = (
        # 学期是第四维范围：'' = 整学年/不限；'上学期' / '下学期' 各算独立点。
        UniqueConstraint("parent_id", "subject", "grade", "name", "semester"),
        Index("ix_knowledgepoint_scope", "parent_id", "subject", "grade", "semester"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    parent_id: uuid.UUID = Field(foreign_key="user.id")
    subject: str = Field(max_length=16)
    grade: int
    # 学期范围维度（ADR-0055 §4 补）：'' = 整学年/不限；'上学期' / '下学期'。
    semester: str = Field(default="", max_length=8)
    name: str = Field(max_length=128)
    status: str = Field(default=KP_STATUS_PENDING, max_length=16)
    source: str = Field(default=KP_SOURCE_EMERGED, max_length=16)
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
