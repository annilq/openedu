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
"""

from datetime import datetime
from uuid import UUID

from sqlmodel import Field, SQLModel


class CoursewareSection(SQLModel):
    """一个讲解环节。前端提交与后端下发**同构**（改序 = 整体覆盖写）。"""

    # 空则由后端生成（新建时前端不必预先发号）；同份课件内唯一。
    id: str = Field(default="", max_length=40)
    kind: str = Field(max_length=32)
    title: str = Field(default="", max_length=128)
    # 教师话术 / 提问卡文案（决策 15）
    script: str = Field(default="", max_length=500)
    # 按 kind 释义（见模块 docstring）
    payload: dict = Field(default_factory=dict)


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
    """新建课件：**走 AI 起草**（决策 2 / §3.4）。

    未配模型时返回 LLM_UNAVAILABLE（ADR-0039：无离线 mock、无内置模型目录），
    不静默产出空课件——空课件等于把「没有内容」伪装成「有内容」（ADR-0066 纪律）。
    """

    knowledge_point_id: UUID
    # 留空则由起草结果取知识点名
    title: str | None = Field(default=None, max_length=128)


class CoursewareUpdate(SQLModel):
    """改课件元信息（不含环节）。只传要改的字段。"""

    title: str | None = Field(default=None, max_length=128)
    status: str | None = Field(default=None, max_length=16)


class CoursewareSectionsUpdate(SQLModel):
    """整体覆盖写环节序列（增 / 删 / 改序都在前端完成，后端只存结果）。"""

    sections: list[CoursewareSection] = []
