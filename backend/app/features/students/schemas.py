"""Students feature request/response schemas (import/export, ADR-0068)."""

from sqlmodel import SQLModel


class StudentImportRowError(SQLModel):
    """单行导入失败的原因（缺列 / 学号冲突），前端逐行展示。"""

    row: int
    reason: str


class StudentImportResult(SQLModel):
    """批量导入回执：成功创建数、跳过数（冲突 / 缺列）、逐行错误。

    整体 HTTP 状态恒为 200（文件本身合法）；单行的失败落在 ``errors`` 里，由前端逐行提示。
    """

    created: int = 0
    skipped: int = 0
    errors: list[StudentImportRowError] = []
