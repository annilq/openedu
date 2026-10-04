"""Pydantic schemas for the materials (资料库) feature（ADR-0055）."""

from datetime import datetime
from uuid import UUID

from sqlmodel import Field, SQLModel


class FolderCreate(SQLModel):
    """新建资料目录。subject / grade 可留空（仅作分组，不参与元数据继承）。"""

    name: str = Field(min_length=1, max_length=128)
    parent_folder_id: UUID | None = None
    subject: str | None = Field(default=None, max_length=16)
    grade: int | None = Field(default=None, ge=1, le=9)


class FolderUpdate(SQLModel):
    """改目录：显式传 null 表示清空（区别于不传 = 不动）。"""

    name: str | None = Field(default=None, min_length=1, max_length=128)
    subject: str | None = Field(default=None, max_length=16)
    grade: int | None = Field(default=None, ge=1, le=9)
    parent_folder_id: UUID | None = None


class FolderResp(SQLModel):
    """目录项（扁平列表，前端组树）。带直接子节点计数供前端显示徽标。"""

    id: UUID
    name: str
    parent_folder_id: UUID | None = None
    subject: str | None = None
    grade: int | None = None
    created_at: datetime | None = None
    material_count: int = 0
    subfolder_count: int = 0


class MaterialResp(SQLModel):
    """资料项（列表 / 详情共用；不含全文——那是给 AI 的，不是给列表页的）。"""

    id: UUID
    folder_id: UUID | None
    name: str
    mime: str
    size_bytes: int
    subject: str | None = None
    grade: int | None = None
    knowledge_points: list[str] = []
    # 向量化状态机（pending/ready/failed/stale）——前端徽标的数据源
    index_state: str
    embed_model: str | None = None
    chunker_ver: str | None = None
    index_error: str | None = None
    text_length: int = 0  # 已解析出的字符数（0 = 解析失败或空文件）
    created_at: datetime | None = None
    indexed_at: datetime | None = None


class UploadResult(SQLModel):
    """上传响应：资料本体 + 元数据提取结果（提取失败不阻塞入库）。"""

    material: MaterialResp
    # extracted = AI 提取成功；skipped_unsafe = 安全闸门拦截；skipped_no_engine =
    # 未配置模型；failed = 引擎报错——四态都照常入库，家长可手动重试提取。
    extraction: str = "extracted"
    extraction_error: str | None = None


class ExtractResult(SQLModel):
    """手动重新提取元数据的响应（与 UploadResult.extraction 同口径）。"""

    material: MaterialResp
    extraction: str = "extracted"
    extraction_error: str | None = None


class MaterialMeta(SQLModel):
    """AI 整篇提取的结构化元数据（模型输出契约）。

    字段刻意宽松（不做 ge/le 约束）：模型输出不可信，校验与收敛在 service 层做——
    严格的 pydantic 校验会把「模型回了 grade=12」变成整次提取的 500。
    """

    subject: str = ""
    grade: int = 0
    knowledge_points: list[str] = Field(default_factory=list)


class KnowledgePointResp(SQLModel):
    """知识点选择器条目（目录优先 + 骨架兜底，ADR-0055 §4）。"""

    # None = 骨架条目（家长确认后才落库获得 id）
    id: UUID | None = None
    name: str
    # pending = 待审（可出题可检索、不计掌握度）；curated = 已转正
    status: str = "curated"
    # emerged = 资料涌现；skeleton = 自编骨架
    source: str = "skeleton"


class KnowledgePointListResp(SQLModel):
    items: list[KnowledgePointResp]
    pending_count: int = 0


class KnowledgePointConfirm(SQLModel):
    """家长确认待审知识点（pending → curated），或批量确认骨架条目落库。"""

    names: list[str] = Field(min_length=1, max_length=50)
    subject: str = Field(max_length=16)
    grade: int = Field(ge=1, le=9)
