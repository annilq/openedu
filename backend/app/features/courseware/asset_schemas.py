"""课件素材 schemas（ADR-0067 §3.5）——**契约文件**，A 线（切片 2）实现、勿改形状。

与资料（Material）分开的意义写在模型 docstring 里：资料是要切分向量化的教材，
素材是要原样投出去的图。首版只做图片（``COURSEWARE_ASSET_MIMES``）。

⚠️ ``url`` 由后端拼好下发，前端不自己拼路径——避免前端重复实现一遍鉴权前缀。
"""

from datetime import datetime
from uuid import UUID

from sqlmodel import SQLModel


class CoursewareAssetResp(SQLModel):
    """一个课件素材（图片）。"""

    id: UUID
    name: str
    mime: str = ""
    size_bytes: int = 0
    width: int | None = None
    height: int | None = None
    created_at: datetime | None = None
    # 可选的知识点关联（T04 素材库按知识点检索）。空 = 不绑特定知识点。
    knowledge_point_id: UUID | None = None
    # 读取该素材原图的相对路径（带 API 前缀，前端直接拼 baseUrl 即可）。
    # 走 ``GET /courseware/assets/{id}/file``，与列表同一鉴权路径。
    url: str = ""
    # 来源标记（T08 / ADR-0067 §3.5·§5）：user_uploaded=教师自传，platform_cc0=平台
    # 预置 CC0 公共素材。picker 据此展示 CC0 角标与来源 / 许可说明。
    source: str = ""
    # CC0 公共素材的来源 URL 与许可类型；非 CC0 恒为空串。
    source_url: str = ""
    license: str = ""


class CoursewareAssetListResp(SQLModel):
    """素材列表。"""

    items: list[CoursewareAssetResp] = []
