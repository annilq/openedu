"""Students feature service：学生列表 + Excel 批量导入（ADR-0068 §2.2）。

「教师↔学生归属校验」已上提为 ``app.core.guard.require_owned_student``，由 REST
路由、service 与 ADR-0033 的业务查询工具**共用同一份**——本模块不再持有一份。
"""

from __future__ import annotations

import io
from uuid import UUID

from openpyxl import Workbook, load_workbook
from sqlmodel import Session

from app.core.config import settings
from app.db.models import User
from app.features.auth.repository import create_user, get_user_by_username
from app.features.auth.schemas import UserCreate
from app.features.students.schemas import (
    StudentImportResult,
    StudentImportRowError,
)

# 导入表头别名：中英文均可识别，提升容错。
_NAME_HEADERS = ("姓名", "name", "学生姓名", "名字", "学生名")
_NO_HEADERS = ("学号", "student", "studentid", "student_id", "学籍号", "学籍", "账号")


def list_students_of(*, session: Session, teacher_id: UUID) -> list[User]:
    """教师名下全部学生。

    收口「学生列表」的读取口径：查询工具不得跨 feature 直连 ``auth`` 仓储
    （ADR-0033 决策 13）。
    """
    from app.features.auth.repository import list_students

    return list_students(session=session, teacher_id=teacher_id)


def _find_column(headers: list[str], candidates: tuple[str, ...]) -> int | None:
    """按候选子串（小写）定位列下标；找不到返回 None。"""
    for idx, header in enumerate(headers):
        if not header:
            continue
        lowered = header.lower()
        if any(cand in lowered for cand in candidates):
            return idx
    return None


def _normalize_student_no(value) -> str:
    """Excel 单元格 → 学号字符串。

    学号常被存成数字（``2021001``）→ 读成 int；或带小数（``2021001.0``）→ 读成 float。
    统一转成无小数纯数字串，避免「2021001.0」这类脏值；其余原样 strip。
    """
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, float):
        return str(int(value)) if value.is_integer() else str(value)
    if isinstance(value, int):
        return str(value)
    return str(value).strip()


def _parse_xlsx(data: bytes, *, max_rows: int) -> tuple[list[str], list[tuple]]:
    """解析 xlsx 首个工作表，返回 (表头列表, 数据行元组列表)。

    空文件 / 缺必要列在调用方检查；行数超过上限直接抛 ``ValueError``（端点转 400）。
    """
    wb = load_workbook(io.BytesIO(data), read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        raise ValueError("文件为空或无法读取工作表")
    headers = [(str(c).strip() if c is not None else "") for c in rows[0]]
    data_rows = rows[1:]
    if len(data_rows) > max_rows:
        raise ValueError(f"超出单次导入行数上限 {max_rows}")
    return headers, data_rows


def import_students_from_xlsx(
    *, session: Session, teacher_id: UUID, data: bytes
) -> StudentImportResult:
    """批量导入学生（ADR-0068 §2.2）。

    - ``username`` = 学号原样（不做拼音 / 前缀 / 去重）；初始密码 = 配置常量。
    - 缺姓名或学号 → 整行跳过并回传行号（不猜测、不半成功）。
    - 学号已存在（含本次批内重复）→ 落 ``skipped``，**不覆盖**。
    - 同文件重复导入全部 ``skipped``（按 ``username`` 判重，幂等）。
    """
    headers, data_rows = _parse_xlsx(data, max_rows=settings.STUDENT_IMPORT_MAX_ROWS)
    name_idx = _find_column(headers, _NAME_HEADERS)
    no_idx = _find_column(headers, _NO_HEADERS)
    if name_idx is None or no_idx is None:
        raise ValueError("缺少必要列：需要「姓名」与「学号」两列")
    if name_idx == no_idx:
        raise ValueError("「姓名」与「学号」不能是同一列")

    result = StudentImportResult()
    seen: set[str] = set()
    for row_no, row in enumerate(data_rows, start=2):
        # 行可能短于表头（缺尾列）→ 用 None 补齐，避免下标越界。
        cells = list(row) + [None] * (len(headers) - len(row))

        name_val = cells[name_idx]
        no_val = cells[no_idx]

        if name_val is None or (isinstance(name_val, str) and not name_val.strip()):
            result.errors.append(StudentImportRowError(row=row_no, reason="缺少姓名"))
            result.skipped += 1
            continue
        username = _normalize_student_no(no_val)
        if not username:
            result.errors.append(StudentImportRowError(row=row_no, reason="缺少学号"))
            result.skipped += 1
            continue

        display_name = str(name_val).strip()
        if username in seen or get_user_by_username(session=session, username=username):
            result.errors.append(
                StudentImportRowError(row=row_no, reason="学号已存在")
            )
            result.skipped += 1
            continue

        create_user(
            session=session,
            user_create=UserCreate(
                username=username,
                display_name=display_name,
                password=settings.STUDENT_DEFAULT_PASSWORD,
            ),
            role="student",
            teacher_id=teacher_id,
        )
        result.created += 1
        seen.add(username)
    return result


def export_students_xlsx(*, session: Session, teacher_id: UUID) -> bytes:
    """导出账号表（ADR-0068 §2.2 配套交付物）：班级 / 姓名 / 学号 / 初始密码。

    未分班学生班级字段标记「未分班」；初始密码与导入配置常量一致，供教师分发。
    与导入共用 openpyxl（同一 xlsx 库，无第二套依赖）。
    """
    from app.features.auth.repository import list_students
    from app.features.classes.service import list_classes

    students = list_students(session=session, teacher_id=teacher_id)
    class_map = {
        c.id: c.name
        for c in list_classes(session=session, teacher_id=teacher_id)
    }

    wb = Workbook()
    ws = wb.active
    ws.append(["班级", "姓名", "学号", "初始密码"])
    for stu in students:
        class_name = class_map.get(stu.class_id, "未分班")
        ws.append(
            [
                class_name,
                stu.display_name,
                stu.username,
                settings.STUDENT_DEFAULT_PASSWORD,
            ]
        )

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()
