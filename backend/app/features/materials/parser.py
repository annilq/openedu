"""资料文本解析（ADR-0055 §9）：PDF / docx / txt / md → 整篇纯文本。

图片 OCR **二期**（依赖重、中文手写识别差，不与首版捆绑）。解析失败抛
:class:`ParseError`，由 service 转成 422 明确告知「这格式读不出字」，绝不
静默存一份空文本让教师以为入库成功。
"""

from __future__ import annotations

import io
from pathlib import Path

# 支持的扩展名（小写）。mime 由客户端自报不可信，以扩展名为准做白名单。
SUPPORTED_EXTS: tuple[str, ...] = (".pdf", ".docx", ".txt", ".md")

_MAX_TEXT_CHARS = 200_000  # 整篇文本上限（约 10 万汉字）：防病态大文件撑爆 DB 行


class ParseError(ValueError):
    """解析失败（格式不支持 / 文件损坏 / 提不出文字）。"""


def extract_text(*, filename: str, data: bytes) -> str:
    """按扩展名分发解析；返回整篇纯文本（已裁剪到上限）。"""
    ext = Path(filename).suffix.lower()
    if ext not in SUPPORTED_EXTS:
        supported = " / ".join(SUPPORTED_EXTS)
        raise ParseError(f"暂不支持 {ext or '无扩展名'} 文件，请上传 {supported}")
    if ext == ".pdf":
        text = _pdf(data)
    elif ext == ".docx":
        text = _docx(data)
    else:  # .txt / .md
        text = _plain(data)
    text = text.strip()
    if not text:
        raise ParseError("未能从文件中提取出文字（可能是扫描图片版 PDF，暂不支持）")
    return text[:_MAX_TEXT_CHARS]


def _pdf(data: bytes) -> str:
    try:
        from pypdf import PdfReader
    except ImportError as e:  # pragma: no cover
        raise ParseError("服务端未安装 PDF 解析组件") from e
    try:
        reader = PdfReader(io.BytesIO(data))
        return "\n".join(page.extract_text() or "" for page in reader.pages)
    except Exception as e:
        raise ParseError("PDF 解析失败：文件可能已损坏") from e


def _docx(data: bytes) -> str:
    try:
        import docx
    except ImportError as e:  # pragma: no cover
        raise ParseError("服务端未安装 docx 解析组件") from e
    try:
        document = docx.Document(io.BytesIO(data))
        return "\n".join(p.text for p in document.paragraphs)
    except Exception as e:
        raise ParseError("docx 解析失败：文件可能已损坏") from e


def _plain(data: bytes) -> str:
    for encoding in ("utf-8", "gb18030"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise ParseError("文本文件不是 UTF-8 / GBK 编码，无法读取")
