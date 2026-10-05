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
    # 学期范围维度（ADR-0055 §2 补）：None = 未设置（继承）；''/上学期/下学期。
    semester: str | None = Field(default=None, max_length=8)


class FolderUpdate(SQLModel):
    """改目录：显式传 null 表示清空（区别于不传 = 不动）。"""

    name: str | None = Field(default=None, min_length=1, max_length=128)
    subject: str | None = Field(default=None, max_length=16)
    grade: int | None = Field(default=None, ge=1, le=9)
    semester: str | None = Field(default=None, max_length=8)
    parent_folder_id: UUID | None = None


class FolderResp(SQLModel):
    """目录项（扁平列表，前端组树）。带直接子节点计数供前端显示徽标。"""

    id: UUID
    name: str
    parent_folder_id: UUID | None = None
    subject: str | None = None
    grade: int | None = None
    semester: str | None = None
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
    semester: str | None = None
    knowledge_points: list[str] = []
    # 向量化状态机（pending/ready/failed/stale）——前端徽标的数据源
    index_state: str
    embed_model: str | None = None
    chunker_ver: str | None = None
    index_error: str | None = None
    text_length: int = 0  # 已解析出的字符数（0 = 解析失败或空文件）
    created_at: datetime | None = None
    indexed_at: datetime | None = None


class MaterialMove(SQLModel):
    """移动资料到目录：``folder_id`` 为 null = 移回根目录（全部）。"""

    folder_id: UUID | None = None


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
    # 默认交互式讲解模板（ADR-0061）：[{kind, inputs, controls, ...}]；null = 暂未配置。
    scenes: list[dict] | None = None
    # 所属学期（ADR-0061 发布任务对接资料库）：'' = 整学年；'上学期' / '下学期'。
    # 「不限学期」查询会并集多个学期，前端据此给知识点加学期后缀标注，
    # 避免家长在跨学期并集里看到同名却不知属于哪个学期。
    semester: str = ""


class KnowledgePointScenesUpdate(SQLModel):
    """教师为知识点编写 / 覆盖默认交互讲解模板（ADR-0061）。

    仅接收 ``scenes``（知识点级模板数组），不做其它字段变更；空数组 = 清空模板。
    """

    scenes: list[dict] = Field(default_factory=list)


class KnowledgePointListResp(SQLModel):
    items: list[KnowledgePointResp]
    pending_count: int = 0
    # 目录来源说明（ADR-0061 §L）：**当前范围没有真实知识点、只剩骨架兜底**时
    # 给出人话解释。骨架是「冷启动不空窗」的通用目录、**不分学期**，所以在没有
    # 资料知识点的范围里，切学期拿到的下拉会逐字相同——不解释就像「联动坏了」。
    notice: str = ""


class KnowledgePointConfirm(SQLModel):
    """家长确认待审知识点（pending → curated），或批量确认骨架条目落库。"""

    names: list[str] = Field(min_length=1, max_length=50)
    subject: str = Field(max_length=16)
    grade: int = Field(ge=1, le=9)
    # 学期范围维度（ADR-0055 §4 补）：'' = 整学年/不限；'上学期' / '下学期'。
    semester: str = Field(default="", max_length=8)
