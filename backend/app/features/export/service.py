"""Service：把一次导出请求编排成 PDF 字节。

路由顺序（也是各层的分工）：
1. ``schemas`` 收请求 → 2. ``repository`` 取数 + 归属守卫 → 3. ``document``
装配（题号 / 分节 / 降级）→ 4. ``renderer`` 编译。

注意：本文件**不得 import ``fastapi`` 或任何 ``router``**——分层不变量
（``tests/ai/test_layering_invariants.py``）会静态扫描 service 层的 import。
"""
from __future__ import annotations

import uuid

from sqlmodel import Session

from app.core.config import settings
from app.core.errors import AppErrorException, ErrCode
from app.features.export import repository
from app.features.export.document import (
    ExportDocument,
    QuestionGroup,
    build_export_document,
    count_questions,
    group_by_subject,
)
from app.features.export.renderer import render_sheet_pdf
from app.features.export.schemas import ExportSheetReq

_SOURCE_VALUES = ("bank", "task", "wrong_book")


def _validate(req: ExportSheetReq) -> None:
    if req.source not in _SOURCE_VALUES:
        raise AppErrorException(
            ErrCode.EXPORT_SOURCE_UNKNOWN, f"未知的导出来源：{req.source}"
        )
    if req.source == "wrong_book" and req.child_id is None:
        raise AppErrorException(
            ErrCode.EXPORT_CHILD_REQUIRED, "导出错题请指定娃娃"
        )


def _bank_title(req: ExportSheetReq, questions: list) -> str:
    if req.title:
        return req.title
    subjects = list(dict.fromkeys(q.subject for q in questions if q.subject))
    knowledge_points = list(
        dict.fromkeys(
            getattr(q, "knowledge_point", "") for q in questions
        )
    )
    knowledge_points = [kp for kp in knowledge_points if kp]
    if len(subjects) == 1:
        base = subjects[0]
        if len(knowledge_points) == 1:
            return f"{base} · {knowledge_points[0]}练习"
        return f"{base} · 练习"
    return "题库练习"


def _wrong_book_title(req: ExportSheetReq) -> str:
    if req.title:
        return req.title
    return "今日复习" if req.due_only else "错题练习"


def build_document(*, session: Session, parent_id: uuid.UUID, req: ExportSheetReq) -> ExportDocument:
    """装配导出文档（不含编译，纯数据库 + 纯函数，可独立测试）。"""
    _validate(req)
    if req.source == "bank":
        questions = repository.load_bank_questions(
            session=session, parent_id=parent_id, question_ids=req.ids
        )
        document = build_export_document(
            title=_bank_title(req, questions),
            groups=group_by_subject(questions),
        )
    elif req.source == "task":
        groups = repository.load_task_groups(
            session=session, parent_id=parent_id, task_ids=req.ids
        )
        if req.title:
            title = req.title
        else:
            titles = [g.heading for g in groups if g.heading]
            title = titles[0] if len(titles) == 1 else "任务练习"
        document = build_export_document(title=title, groups=groups)
    else:
        assert req.child_id is not None  # _validate 已保证
        questions = repository.load_wrong_book_questions(
            session=session,
            parent_id=parent_id,
            child_id=req.child_id,
            due_only=req.due_only,
        )
        document = build_export_document(
            title=_wrong_book_title(req), groups=group_by_subject(questions)
        )

    if count_questions(document) == 0:
        raise AppErrorException(ErrCode.EXPORT_EMPTY, "选中的题目取不到内容，无法导出")
    if count_questions(document) > settings.EXPORT_MAX_QUESTIONS:
        raise AppErrorException(
            ErrCode.EXPORT_TOO_MANY,
            f"单次导出最多 {settings.EXPORT_MAX_QUESTIONS} 题，请分批导出",
        )
    return document


def build_sheet_pdf(*, session: Session, parent_id: uuid.UUID, req: ExportSheetReq) -> bytes:
    """完整链路：装配 + 编译。CPU 密集的编译由路由层放进线程池执行。"""
    document = build_document(session=session, parent_id=parent_id, req=req)
    return render_sheet_pdf(document)


__all__ = ["build_document", "build_sheet_pdf", "QuestionGroup"]
