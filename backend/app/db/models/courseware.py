"""课件两表（ADR-0067）：知识点驱动的课堂讲解环节。

课件是 ``KnowledgePoint.scenes`` 的**上位容器**——scenes 是「一个知识点 → 一份
交互场景模板」，课件是「一个知识点 → 一串有序、类型各异的环节」。两者并存，不合并。

归属纪律：两表全部带 ``teacher_id``，越权校验只走 ``core.guard``，不新增鉴权路径
（ADR-0055 §1 / ADR-0067 §3.2）。

外键纪律：**课件不建 FK 约束**（只有索引）。ADR-0064 的「删资料 → 清理孤儿知识点」
会删掉知识点行，若这里挂外键，要么删除失败、要么留悬垂引用。课件对知识点是
**快照引用**（ADR-0055 §10 同款纪律）：``knowledge_point_id`` 仅用于「选得到」，
展示一律用 ``kp_name`` 快照，知识点被清理后 id 置空、课件存活（ADR-0067 §4.1）。

迁移纪律：全新表，``init_db`` 的 ``create_all`` 自动建表，无需启动期 ALTER
（与 ADR-0055 四表同款）；索引随表定义走（ADR-0053：不引 alembic）。
"""

import uuid
from datetime import datetime

from sqlalchemy import JSON, DateTime, Index
from sqlmodel import Field, SQLModel

from app.db.models.base import get_datetime_utc

# ── 课件状态（ADR-0067 §3.2）─────────────────────────────────────────────
# draft = 起草后教师还在调；ready = 可以直接上讲台。
# ⚠️ 状态**不阻塞演示**：draft 也能开讲，它只是列表上的筛选标签。
COURSEWARE_STATUS_DRAFT = "draft"
COURSEWARE_STATUS_READY = "ready"
COURSEWARE_STATUSES: tuple[str, ...] = (
    COURSEWARE_STATUS_DRAFT,
    COURSEWARE_STATUS_READY,
)

# ── 环节 kind 注册表（ADR-0067 §3.3）─────────────────────────────────────
# ⚠️ 这是**环节类型**，与 ADR-0061 的 SceneSpec kind（渲染器名 reflection /
# bar_chart / …）是两层。``interactive_scene`` 这个字符串在两层各出现一次、
# 语义不同，**两套注册表各自登记、各自契约测试，禁止互相映射复用**。
SECTION_KIND_MEDIA_GALLERY = "media_gallery"  # 生活素材 / 欣赏（环节 1、3）
SECTION_KIND_INTERACTIVE_SCENE = "interactive_scene"  # 交互判定（环节 2）
SECTION_KIND_PRACTICE = "practice"  # 课堂练习（环节 4）
SECTION_KINDS: tuple[str, ...] = (
    SECTION_KIND_MEDIA_GALLERY,
    SECTION_KIND_INTERACTIVE_SCENE,
    SECTION_KIND_PRACTICE,
)

# ── 课件素材允许的 MIME（ADR-0067 §3.5：首版只做图片）─────────────────────
# 与资料（Material）分开：材料是要切分 + 向量化的教材（parser 只吃
# .pdf/.docx/.txt/.md），素材是要原样显示的图，不进向量库。
COURSEWARE_ASSET_MIMES: tuple[str, ...] = (
    "image/png",
    "image/jpeg",
    "image/webp",
    "image/gif",
)

# ── 素材来源 ───────────────────────────────────────────────────────────────
# 首版只做教师自传图片（ADR-0077：移除 platform_cc0 预置包，素材库 = 纯教师上传）。
COURSEWARE_ASSET_SOURCE_USER_UPLOADED = "user_uploaded"


class Courseware(SQLModel, table=True):
    """一份课件 = 一个知识点上的一串讲解环节（ADR-0067 §3.2）。

    一个知识点可有多份课件（不同教师 / 同一教师的不同讲法），故不把课件并入
    KnowledgePoint 行——那会让行继续膨胀且限死一份。
    """

    __table_args__ = (
        Index("ix_courseware_teacher_scope", "teacher_id", "subject", "grade"),
        Index("ix_courseware_teacher_kp", "teacher_id", "knowledge_point_id"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    teacher_id: uuid.UUID = Field(foreign_key="user.id")
    # 范围三选快照（取自知识点，冗余存放：列表按范围筛、不 join）
    subject: str | None = Field(default=None, max_length=16)
    grade: int | None = None
    semester: str | None = Field(default=None, max_length=8)
    # 快照引用（无 FK 约束，见模块 docstring）：知识点被清理时置 None
    knowledge_point_id: uuid.UUID | None = Field(default=None, index=True)
    # 冗余快照：保证知识点被删后课件不会变成无名课件
    kp_name: str = Field(default="", max_length=128)
    title: str = Field(default="", max_length=128)
    status: str = Field(default=COURSEWARE_STATUS_DRAFT, max_length=16)
    # 教学目标 / 备注（courseware-round-3 T01）：空壳课件建出时存教师填的备课依据，
    # 供后续「AI 补充讲解」（T05）读取当作起草上下文。可空、无索引、无 FK。
    objective: str | None = Field(default=None, max_length=2000)
    # 环节序列：[{id, kind, title, script, payload}]。整体覆盖写，不建子表
    # （ADR-0067 §3.2：子表只带来 JOIN 与孤儿行）。
    #
    # `none_as_null=True` 是关键：SQLAlchemy 的 JSON 类型默认把 Python ``None``
    # 序列化成 JSON 字符串 ``'null'``（**不是** SQL NULL），于是「清空环节」写进去
    # 的是文本 ``null``——`IS NOT NULL` 为真、内容却是空的，任何「有环节」判断都会
    # 走偏（ADR-0061 §M 实测踩过）。
    sections: list[dict] | None = Field(default=None, sa_type=JSON(none_as_null=True))
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    updated_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )


class CoursewareAsset(SQLModel, table=True):
    """课件素材：一张要原样投出去的图（ADR-0067 §3.5）。

    独立建表而非塞进 Material：资料是要切分、向量化的教材，素材只负责显示，
    不进向量库、不切分、不参与检索。物理存储复用
    ``MATERIAL_UPLOAD_ROOT/{teacher_id}/{key}``（已有 per-teacher 目录机制）。

    删除语义（ADR-0067 §4.2 / 决策 10）：**允许删**，不维护引用计数。删后引用它的
    环节显示「素材已移除」占位——「删不掉」比「出现空洞」更让人恼火。
    """

    __table_args__ = (
        Index("ix_coursewareasset_teacher", "teacher_id"),
        Index("ix_coursewareasset_kp", "knowledge_point_id"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    teacher_id: uuid.UUID = Field(foreign_key="user.id")
    # 可选的知识点关联：素材库可按知识点检索（T04）。为空 = 通用素材（不绑特定知识点）。
    knowledge_point_id: uuid.UUID | None = Field(default=None, foreign_key="knowledgepoint.id")
    name: str = Field(default="", max_length=255)  # 展示名（原始文件名）
    storage_key: str = Field(default="", max_length=512)  # 落盘相对路径
    mime: str = Field(default="", max_length=64)
    size_bytes: int = Field(default=0)
    # 宽高用于演示页排版（未知则为 None，布局按可用宽度自适应）
    width: int | None = None
    height: int | None = None
    # 来源标记：user_uploaded=教师自传（ADR-0077 起素材库 = 纯教师上传，无平台预置素材）。
    source: str = Field(
        default=COURSEWARE_ASSET_SOURCE_USER_UPLOADED, max_length=32
    )
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
