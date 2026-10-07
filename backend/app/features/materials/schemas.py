"""Pydantic schemas for the materials (资料库) feature（ADR-0055）."""

from datetime import datetime
from uuid import UUID

from sqlmodel import Field, SQLModel


class FolderCreate(SQLModel):
    """新建资料目录。subject / grade 可留空（仅作分组，不参与元数据继承）。"""

    name: str = Field(min_length=1, max_length=128)
    teacher_folder_id: UUID | None = None
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
    teacher_folder_id: UUID | None = None


class FolderResp(SQLModel):
    """目录项（扁平列表，前端组树）。带直接子节点计数供前端显示徽标。"""

    id: UUID
    name: str
    teacher_folder_id: UUID | None = None
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


class MaterialDelete(SQLModel):
    """批量删除资料（多选）。

    ``cascade_knowledge_points`` 为真时顺带清理**孤儿知识点**——仅由这批资料
    涌现、且没有任何其它资料还在引用、也从未被教师确认过的知识点
    （见 ``service.delete_materials`` 的口径）。默认关闭，保证删除语义默认最小。
    """

    ids: list[UUID] = Field(min_length=1, max_length=100)
    cascade_knowledge_points: bool = False


class KnowledgePointDelete(SQLModel):
    """批量删除知识点（多选）。骨架条目没有 id，只能删已落库的行。"""

    ids: list[UUID] = Field(min_length=1, max_length=200)


class UploadResult(SQLModel):
    """上传响应：资料本体 + 元数据提取结果（提取失败不阻塞入库）。"""

    material: MaterialResp
    # extracted = AI 提取成功；skipped_unsafe = 安全闸门拦截；skipped_no_engine =
    # 未配置模型；failed = 引擎报错——四态都照常入库，教师可手动重试提取。
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

    # None = 骨架条目（教师确认后才落库获得 id）
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
    # 避免教师在跨学期并集里看到同名却不知属于哪个学期。
    semester: str = ""


class KnowledgePointScenesUpdate(SQLModel):
    """教师为知识点编写 / 覆盖默认交互讲解模板（ADR-0061）。

    仅接收 ``scenes``（知识点级模板数组），不做其它字段变更；空数组 = 清空模板。
    """

    scenes: list[dict] = Field(default_factory=list)


class KnowledgePointScopeResp(SQLModel):
    """一个「教师真的上传过教材」的知识点范围（ADR-0065）。

    学科 / 年级取自资料本身；学期口径与知识点诞生时**逐字一致**（见 service
    ``knowledge_point_scope``）——不一致的话教师选中了这个范围却查不到
    当初涌现出来的知识点，等于把入口做成死的。
    """

    subject: str
    grade: int
    semester: str
    material_count: int = 0


class KnowledgePointScopeListResp(SQLModel):
    """可选范围清单；空列表 = 一份教材都还没上传。

    [unscoped_count] 是**学科或年级缺失**的资料数（提取没跑出来 / 还没提取）。
    它们没法归到任何范围，知识点管理页必须把这件事说出来——否则教师传了资料却在
    下拉里找不到对应年级，只会以为上传丢了。
    """

    scopes: list[KnowledgePointScopeResp] = Field(default_factory=list)
    unscoped_count: int = 0


class KnowledgePointListResp(SQLModel):
    items: list[KnowledgePointResp]
    pending_count: int = 0
    # 空目录的**原因**（给教师看的一句话）：这个范围压根没上传过教材？还是传了但
    # 还没识别出知识点？空列表本身不解释任何事，教师不知道下一步做什么。
    notice: str = ""


class KnowledgePointConfirm(SQLModel):
    """教师确认待审知识点（pending → curated），或批量确认骨架条目落库。"""

    names: list[str] = Field(min_length=1, max_length=50)
    subject: str = Field(max_length=16)
    grade: int = Field(ge=1, le=9)
    # 学期范围维度（ADR-0055 §4 补）：'' = 整学年/不限；'上学期' / '下学期'。
    semester: str = Field(default="", max_length=8)


class SceneLibraryKpRef(SQLModel):
    """场景库里的「关联知识点」条目（ADR-0073 浏览页语义边界）。

    它回答的是「这个内置场景被哪些知识点引用了」，浏览页据此列出「内置实例」。
    带 ``subject/grade/semester`` 是因为知识点是**跨学期同名的**（唯一约束含
    学期）——只给 name 会让教师看到三个「轴对称」却分不清是谁。
    """

    id: UUID
    name: str
    subject: str
    grade: int
    semester: str
    # 该知识点自己的完整场景（`KnowledgePoint.scenes`）原样透传：浏览页详情要显示
    # 「这个实例配的是哪个图形」——只给名字的话教师看到三个「轴对称」，还得逐
    # 个点进去才知道各配了什么。None = 该知识点还没配。
    scenes: list[dict] | None = None


class SceneLibraryItem(SQLModel):
    """一个内置场景（注册表条目）+ 它的关联知识点。

    ``defaults`` 是**完整的 SceneSpec 中性种子**，不是扁平的参数列表：编辑器选中
    某个 kind 后直接拿它预填表单并即时预览，前端就不必再手拼一份结构（那正是
    原先 ``_buildSpec`` 与后端互为镜像的重复来源）。
    """

    kind: str
    title: str = ""
    # 完整 SceneSpec（含 inputs / controls / narrative / outputs），中性种子。
    defaults: dict = Field(default_factory=dict)
    associated_knowledge_points: list[SceneLibraryKpRef] = Field(default_factory=list)
    # 「内置实例数量」= 关联知识点数（浏览页共识）：统计的是**内置参考**，
    # 不含已生成的题目/课件快照。
    instance_count: int = 0


class SceneLibraryResp(SQLModel):
    """场景库清单。空 scenes 列表 = 注册表为空（属部署异常，正常至少有 reflection）。"""

    scenes: list[SceneLibraryItem] = Field(default_factory=list)
