"""资料文本解析（ADR-0055 §9 / ADR-0092）：PDF / docx / txt / md → 整篇纯文本。

两层处理：

1. **乱码清洗（默认开，零新依赖）**——教材封面页的 EAN-13 条码（符号字体、
   ToUnicode 损坏，被 pypdf 解成私用区码位）与「绿色印刷产品」防复印水印（被解成
   ``cmmmcmm…`` 字母噪声）不是文字，OCR 也修不了。``clean_text`` 直接按字符类清掉
   私用区 / 控制符 / 替换符 + 绿印水印长串。

2. **OCR 兜底（逐页，仅真·扫描页触发）**——某页文本层抽不出字（扫描件 / 图片型
   PDF 页）时，用 PyMuPDF 光栅化该页、RapidOCR 识别。判定阈值参照 Apache Tika
   ``OcrConfig.StrategyAuto(10,10)``：一页有效文字 < 10 字符，或含 > 10 个未映射
   Unicode 字符，即判为扫描页。封面页有真实文字 + 噪声，不会被误判。

解析全程产出 :class:`ParseReport`，记录清理字符数 / 扫描页数 / OCR 页数 / 告警，供
上传后「解析校验」在 UI 呈现（ADR-0092）。OCR 引擎与光栅化依赖**懒加载**：缺组件时
扫描页退化为告警而非抛 500，应用照常启动。
"""

from __future__ import annotations

import dataclasses
import io
import re
from pathlib import Path

# 支持的扩展名（小写）。mime 由客户端自报不可信，以扩展名为准做白名单。
SUPPORTED_EXTS: tuple[str, ...] = (".pdf", ".docx", ".txt", ".md")

_MAX_TEXT_CHARS = 200_000  # 整篇文本上限（约 10 万汉字）：防病态大文件撑爆 DB 行
_PAGE_MAX_CHARS = 20_000  # 单页字符上限：个别超长页（如整页公式图 OCR 误读）截断

# 扫描页判定阈值（参照 Apache Tika OcrConfig.StrategyAuto(10,10)）：
# 一页「清洗后有效文字」< _SCAN_MIN_CHARS，或「原始未映射字符」> _SCAN_MAX_UNMAPPED，
# 即判定为扫描页 → 走 OCR。教材正文页实测 175–418 字符/页，扫描页 0–30，两侧各一个
# 数量级余量，不会误伤正常页。
_SCAN_MIN_CHARS = 10
_SCAN_MAX_UNMAPPED = 10

# 乱码字符类：私用区（条码符号字体）/ 替换符 / C0+C1 控制符（除空白）。
_UNMAPPED_RE = re.compile(r"[\uE000-\uF8FF\uFFFD\x00-\x08\x0b\x0c\x0e-\x1f]")
# 绿印水印：被解成 c/m 长串（中文无连续 5+ 的 c/m；"cm" 单位仅 2 字符，安全）。
_WATERMARK_RE = re.compile(r"[cm]{5,}")


@dataclasses.dataclass
class ParseReport:
    """解析结果 + 校验元数据（ADR-0092）。

    ``warnings`` 是人话告警列表，直接喂给前端「解析校验」面板：
    - 已清理 N 个乱码字符（封面条码 / 绿印水印）
    - 检测到 M 页为扫描页，已自动 OCR 识别
    - 检测到 M 页疑似扫描页，但 OCR 组件未安装，未能识别文字
    """

    text: str = ""
    warnings: list[str] = dataclasses.field(default_factory=list)
    original_chars: int = 0
    cleaned_chars: int = 0
    scan_pages: int = 0
    ocr_pages: int = 0
    pages: int = 0

    def to_meta(self) -> dict:
        return {
            "original_chars": self.original_chars,
            "cleaned_chars": self.cleaned_chars,
            "scan_pages": self.scan_pages,
            "ocr_pages": self.ocr_pages,
            "pages": self.pages,
            "warnings": self.warnings,
        }


class ParseError(ValueError):
    """解析失败（格式不支持 / 文件损坏 / 提不出文字）。"""


def clean_text(raw: str) -> tuple[str, int]:
    """清掉乱码字符，返回 (清理后文本, 清理掉的字符数)。

    清两类：①私用区 / 控制符 / 替换符（条码、损坏 ToUnicode）；②绿印水印的
    ``c/m`` 长串。返回清理数用于「解析校验」呈现。
    """
    cleaned = _UNMAPPED_RE.sub("", raw)
    cleaned = _WATERMARK_RE.sub("", cleaned)
    return cleaned, len(raw) - len(cleaned)


def _count_unmapped(s: str) -> int:
    return len(_UNMAPPED_RE.findall(s))


def _is_scan_page(*, raw: str, cleaned: str) -> bool:
    """该页是否应走 OCR：清洗后有效文字过少，或原始未映射字符过多。"""
    if len(cleaned.strip()) < _SCAN_MIN_CHARS:
        return True
    if _count_unmapped(raw) > _SCAN_MAX_UNMAPPED:
        return True
    return False


def _rasterize_and_ocr(data: bytes, page_indices: list[int]) -> dict[int, str]:
    """对指定页光栅化并 OCR，返回 {页索引: 识别文本}。缺组件时返回 {}。

    依赖懒加载：PyMuPDF 光栅化（cp310-abi3 wheel 兼容 3.14）+ RapidOCR 识别
    （PP-OCRv6 small 模型，自带于 rapidocr wheel）。任一缺失即返回空，由调用方
    退化为告警，不抛异常、不阻塞入库。
    """
    try:
        import fitz  # PyMuPDF
    except ImportError:
        return {}
    try:
        from PIL import Image
        from rapidocr import RapidOCR
    except ImportError:
        return {}
    engine = RapidOCR()
    out: dict[int, str] = {}
    doc = fitz.open(stream=data, filetype="pdf")
    try:
        for i in page_indices:
            if i >= len(doc):
                continue
            pix = doc[i].get_pixmap(dpi=200)
            img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
            ocr_out = engine(img)
            # rapidocr >= 3.x 返回 RapidOCROutput 数据类（含 .txts）；极少见的旧版
            # 返回 (boxes, txts, scores) 元组——两种都只取纯文本行，保证扫描页识别可用。
            if hasattr(ocr_out, "txts"):
                texts = [t for t in (ocr_out.txts or []) if isinstance(t, str)]
            elif isinstance(ocr_out, tuple) and ocr_out:
                _txts = ocr_out[1] if len(ocr_out) >= 2 else ocr_out[0]
                texts = [
                    (r[1] if isinstance(r, (list, tuple)) and len(r) >= 2 else r)
                    for r in _txts
                ]
            else:
                texts = []
            out[i] = "\n".join(texts)
    finally:
        doc.close()
    return out


def _pdf_report(data: bytes) -> ParseReport:
    try:
        from pypdf import PdfReader
    except ImportError as e:  # pragma: no cover
        raise ParseError("服务端未安装 PDF 解析组件") from e
    try:
        reader = PdfReader(io.BytesIO(data))
    except Exception as e:
        raise ParseError("PDF 解析失败：文件可能已损坏") from e

    report = ParseReport(pages=len(reader.pages))
    scan_indices: list[int] = []
    parts: list[str] = []
    for i, page in enumerate(reader.pages):
        raw = page.extract_text() or ""
        cleaned, removed = clean_text(raw)
        report.original_chars += len(raw)
        report.cleaned_chars += removed
        if _is_scan_page(raw=raw, cleaned=cleaned):
            scan_indices.append(i)
            parts.append("")  # 占位，OCR 后回填
        else:
            if len(cleaned) > _PAGE_MAX_CHARS:
                cleaned = cleaned[:_PAGE_MAX_CHARS]
            parts.append(cleaned)

    if scan_indices:
        ocr_result = _rasterize_and_ocr(data, scan_indices)
        report.scan_pages = len(scan_indices)
        if ocr_result:
            report.ocr_pages = len(ocr_result)
            for i, txt in ocr_result.items():
                parts[i] = clean_text(txt)[0]
        if report.ocr_pages == 0:
            report.warnings.append(
                f"检测到 {report.scan_pages} 页疑似扫描页，但 OCR 组件未安装，"
                "未能识别其中的文字（请在依赖中安装 rapidocr + pymupdf）"
            )
        else:
            report.warnings.append(
                f"检测到 {report.ocr_pages} 页为扫描页，已自动 OCR 识别"
            )

    text = "\n".join(parts).strip()
    if report.cleaned_chars > 0 and report.ocr_pages == 0:
        report.warnings.append(
            f"已清理 {report.cleaned_chars} 个乱码字符（封面条码 / 绿印水印）"
        )
    report.text = text[:_MAX_TEXT_CHARS]
    return report


def _docx_report(data: bytes) -> ParseReport:
    try:
        import docx
    except ImportError as e:  # pragma: no cover
        raise ParseError("服务端未安装 docx 解析组件") from e
    try:
        document = docx.Document(io.BytesIO(data))
        raw = "\n".join(p.text for p in document.paragraphs)
    except Exception as e:
        raise ParseError("docx 解析失败：文件可能已损坏") from e
    cleaned, removed = clean_text(raw)
    report = ParseReport(
        text=cleaned[:_MAX_TEXT_CHARS],
        original_chars=len(raw),
        cleaned_chars=removed,
        pages=len(document.paragraphs),
    )
    if removed > 0:
        report.warnings.append(f"已清理 {removed} 个乱码字符")
    return report


def _plain_report(data: bytes) -> ParseReport:
    raw = None
    for encoding in ("utf-8", "gb18030"):
        try:
            raw = data.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    if raw is None:
        raise ParseError("文本文件不是 UTF-8 / GBK 编码，无法读取")
    cleaned, removed = clean_text(raw)
    report = ParseReport(
        text=cleaned[:_MAX_TEXT_CHARS],
        original_chars=len(raw),
        cleaned_chars=removed,
        pages=1,
    )
    if removed > 0:
        report.warnings.append(f"已清理 {removed} 个乱码字符")
    return report


def parse_material(*, filename: str, data: bytes) -> ParseReport:
    """按扩展名分发解析，返回 :class:`ParseReport`（已裁剪到上限）。

    空文本抛 :class:`ParseError`——由 service 转成 422 明确告知「这格式读不出字」，
    绝不静默存一份空文本让教师以为入库成功（ADR-0055 §9 纪律）。
    """
    ext = Path(filename).suffix.lower()
    if ext not in SUPPORTED_EXTS:
        supported = " / ".join(SUPPORTED_EXTS)
        raise ParseError(f"暂不支持 {ext or '无扩展名'} 文件，请上传 {supported}")
    if ext == ".pdf":
        report = _pdf_report(data)
    elif ext == ".docx":
        report = _docx_report(data)
    else:  # .txt / .md
        report = _plain_report(data)
    if not report.text:
        raise ParseError("未能从文件中提取出文字（可能是扫描图片版 PDF，暂不支持）")
    return report


def extract_text(*, filename: str, data: bytes) -> str:
    """向后兼容：返回清洗后的整篇纯文本（不含校验元数据）。"""
    return parse_material(filename=filename, data=data).text
