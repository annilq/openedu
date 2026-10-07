"""Students feature request/response schemas (import/export, ADR-0068)."""

from uuid import UUID

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


class StudentBatchReassignReq(SQLModel):
    """批量移入/移出班级（ticket 03）。

    ``class_id`` 为 ``None`` 表示把学生移出班级（归入未分班）；否则移入该班级。
    整批在同一个事务内完成：任一学生/班级不属于当前教师即整体失败、全部回滚。
    """

    class_id: UUID | None = None
    student_ids: list[UUID]


class StudentBatchReassignResp(SQLModel):
    """批量重分班回执：实际改动的行数（已在该班/未分班的跳过不计）。"""

    updated: int
    class_id: UUID | None = None
