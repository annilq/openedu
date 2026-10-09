"""课件 schemas（ADR-0067）——**契约文件**，C 线（切片 3）实现、勿改形状。

四份契约之一：前后端逐字段对齐的 REST JSON。改这里 = 改契约，必须同步
``frontend/lib/features/courseware/domain/models/*.dart``。

环节（section）的统一形状：``{id, kind, title, script, payload}``。

- ``kind`` 只取注册表常量（SECTION_KINDS），**不接受自由字符串**。
- ``script`` 是教师话术（「这些图形有什么共同点？」）。按决策 15，它**当提问卡
  直接投给学生看**，不折叠、不做「仅教师可见」——投影时教师屏 = 学生所见。
- ``payload`` 按 kind 释义，schema 层**不做多态校验**（那是 kind 各自的事）：
  - ``media_gallery``: ``{items: [{asset_id, caption}], }``
  - ``interactive_scene``: **直接嵌一份 ADR-0061 的 SceneSpec**（原样透传）
  - ``practice``: ``{qtype, count}``
- ``materials`` / ``scene`` 是与 kind **解耦**的顶层可选字段（环节内容块统一化）：
  任何 kind 的环节都能挂素材（``[{asset_id, caption}]``）与关联知识点场景
  （ADR-0061 SceneSpec）。旧 AI 起草数据仍走 ``payload`` 内嵌（items / 整份
  SceneSpec），由前端回退读取；新数据优先走顶层字段。
"""

from datetime import datetime
from uuid import UUID

from sqlmodel import Field, SQLModel


class CoursewareScriptSegment(SQLModel):
    """话术里的一段（ADR-0067 第二轮 T02）：可带轻量重点标注。

    - ``text`` 是这段提问卡文案；
    - ``emphasis`` 只取 ``none`` / ``bold`` / ``highlight``（轻量富文本，不引入新引擎）。
    """

    text: str = Field(default="", max_length=2000)
    emphasis: str = Field(default="none", max_length=16)


class CoursewareSection(SQLModel):
    """一个讲解环节。前端提交与后端下发**同构**（改序 = 整体覆盖写）。"""

    # 空则由后端生成（新建时前端不必预先发号）；同份课件内唯一。
    id: str = Field(default="", max_length=40)
    # courseware-round-3 T03（去 kind·expand）：环节不再按 kind 类型化，改为「内容块
    # 统一渲染」——kind 退化为**可选只读**的旧数据兼容字段。新数据可不带 kind；空 /
    # 未知 kind 都不再 422（删 kind 字段与枚举归 T07 contract）。
    kind: str | None = Field(default=None, max_length=32)
    title: str = Field(default="", max_length=128)
    # 教师话术 / 提问卡文案（决策 15）。首轮单串legacy仍保留：T02 之后新数据走
    # ``script_segments``，旧单串课件靠它向下兼容（见 domain 的 displaySegments 回退）。
    # ⚠️ max_length 放宽到 2000：多段话术压平进 script 后可能超过原 500。
    script: str = Field(default="", max_length=2000)
    # 话术多段化（T02）：有序段列表，每段可带重点。空列表 = 退化为读 script。
    script_segments: list[CoursewareScriptSegment] = Field(default_factory=list)
    # 按 kind 释义（见模块 docstring）
    payload: dict = Field(default_factory=dict)
    # 素材（环节内容块统一化）：任何 kind 都能挂，与 payload['items'] 并存过渡。
    # 新数据走这里；旧 AI 起草数据（payload['items']）由前端回退读取。
    materials: list[dict] = Field(default_factory=list)
    # 关联的知识点交互场景（ADR-0061 SceneSpec），任何 kind 都能挂，与 payload
    # 内嵌 SceneSpec（interactive_scene 旧结构）并存过渡。
    scene: dict | None = Field(default=None)
    # courseware-round-3 T06（去 kind·expand 后的练习内容块）：课堂练习配置
    # {qtype, count, hints}。与 materials / scene 并列的第四可选内容块，任何环节
    # 都能挂；旧 AI 起草数据走 payload['qtype'] 由前端回退读取。
    practice: dict | None = Field(default=None)


class CoursewareResp(SQLModel):
    """一份课件（含环节序列）。"""

    id: UUID
    subject: str | None = None
    grade: int | None = None
    semester: str | None = None
    knowledge_point_id: UUID | None = None
    # 知识点名快照：知识点被 ADR-0064 清理后仍可读（§4.1）
    kp_name: str = ""
    title: str = ""
    status: str = "draft"
    sections: list[CoursewareSection] = []
    section_count: int = 0
    # True = 该课件所属知识点已被清理（孤儿课件）。列表据此标注，课件仍可用。
    kp_missing: bool = False
    created_at: datetime | None = None
    updated_at: datetime | None = None


class CoursewareCreate(SQLModel):
    """新建课件。

    - ``draft=True``（默认）：走 AI 起草（决策 2 / §3.4）。未配模型时返回
      LLM_UNAVAILABLE（ADR-0039），不静默产出空课件。
    - ``draft=False``（courseware-round-3 T01）：跳过 AI 起草，只按知识点快照建
      **零环节空壳**课件（不调模型、不抛 LLM 错误），教师随后手动填/用「AI 补充
      讲解」补环节。``objective`` 一并落到课件行，供后续 AI 补充读取（T05）。
    """

    knowledge_point_id: UUID
    # 留空则回落知识点名（空壳与 AI 起草都用这条回落）。
    title: str | None = Field(default=None, max_length=128)
    # courseware-round-3 T01：是否自动 AI 起草。False = 建空壳（不调模型）。
    draft: bool = True
    # 教学目标 / 备注（可选）：空壳建出时存教师填的备课依据，AI 补充讲解时读取。
    objective: str | None = Field(default=None, max_length=2000)


class CoursewareUpdate(SQLModel):
    """改课件元信息（不含环节）。只传要改的字段。"""

    title: str | None = Field(default=None, max_length=128)
    status: str | None = Field(default=None, max_length=16)


class CoursewareSectionsUpdate(SQLModel):
    """整体覆盖写环节序列（增 / 删 / 改序都在前端完成，后端只存结果）。"""

    sections: list[CoursewareSection] = []


class SectionDiffItem(SQLModel):
    """重起草时，新草稿相对当前稿的一处逐段差异。

    - ``status``: ``added`` / ``removed`` / ``modified`` / ``unchanged``；
    - ``current``: 当前稿里的那段（``removed`` / ``modified`` / ``unchanged`` 有值）；
    - ``drafted``: 草稿里的那段（``added`` / ``modified`` / ``unchanged`` 有值）。
    """

    status: str = "unchanged"
    current: CoursewareSection | None = None
    drafted: CoursewareSection | None = None


class CoursewareRedraftDiff(SQLModel):
    """重起草的逐段 diff（对照当前课件环节）。前端据此渲染预览，教师逐段选择后
    把合并结果经 ``PUT /sections`` 写回**同一份**课件（不新建副本）。"""

    diff: list[SectionDiffItem] = []
