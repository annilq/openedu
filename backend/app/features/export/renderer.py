"""Typst 渲染：导出文档 → PDF 字节。

模板与数据的关系是单向的：服务端把装配好的导出文档经 ``sys_inputs`` 以 JSON
传入 ``.typ`` 模板，模板**只画不算**（题号、留白形态、有没有选项都是装配阶段
定好的）。客户端拿到的是 PDF 字节，永远不接触模板。
"""
from __future__ import annotations

import json
from dataclasses import asdict
from pathlib import Path
from typing import TYPE_CHECKING

import typst

from app.features.export.fonts import require_font_dir

if TYPE_CHECKING:
    from app.features.export.document import ExportDocument

_TEMPLATE_PATH = Path(__file__).parent / "templates" / "student_sheet.typ"

# 系统字体一律关闭：不忽略的话，同一份数据在不同机器上会挑到不同的中文字体
# （macOS 有 PingFang，精简容器里什么都没有），「预览与打印不一致」就会从
# 构造上不可能变成环境性的偶现。字体只认 EXPORT_FONT_DIR。
_IGNORE_SYSTEM_FONTS = True


def render_sheet_pdf(document: ExportDocument) -> bytes:
    font_dir = require_font_dir()
    payload = json.dumps(asdict(document), ensure_ascii=False)
    pdf = typst.compile(
        input=_TEMPLATE_PATH,
        format="pdf",
        font_paths=[str(font_dir)],
        ignore_system_fonts=_IGNORE_SYSTEM_FONTS,
        sys_inputs={"data": payload},
    )
    if not isinstance(pdf, bytes) or not pdf.startswith(b"%PDF-"):
        raise RuntimeError("Typst 编译结果不是有效的 PDF")
    return pdf
