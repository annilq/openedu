"""parser 单测（ADR-0092）：乱码清洗 + 扫描页判定 + OCR 兜底路径。

不依赖真实 PDF / OCR 引擎：pypdf.PdfReader 与 ``_rasterize_and_ocr`` 均用 monkeypatch
替换，验证解析逻辑本身。OCR 引擎缺失时的降级告警也单独覆盖。
"""

from __future__ import annotations

import pytest

from app.features.materials.parser import (
    ParseError,
    ParseReport,
    clean_text,
    parse_material,
)


def test_clean_text_removes_barcode_pua_and_watermark():
    raw = (
        "速度×时间=路程"
        "\uf000\uf001OJOEE"  # 条码符号字体（私用区）
        "绿色印刷产品 cmmmcmmmmmcmmcmmmmmcmmcmmmccmcmcm"  # 绿印水印噪声
        "例1"
    )
    cleaned, removed = clean_text(raw)
    assert "\uf000" not in cleaned
    assert "cmmmc" not in cleaned
    assert "速度×时间=路程" in cleaned
    assert "例1" in cleaned
    assert removed == len(raw) - len(cleaned)
    assert removed > 0


def test_clean_text_keeps_legit_cm_units():
    s = "小明有5cm长的铅笔，面积是12平方厘米。"
    cleaned, removed = clean_text(s)
    assert removed == 0
    assert "5cm" in cleaned  # 单位 cm 仅 2 字符，不被水印规则误删
    assert "平方厘米" in cleaned


def test_parse_material_rejects_unsupported_extension():
    with pytest.raises(ParseError):
        parse_material(filename="cover.png", data=b"x")


def test_pdf_text_pages_get_cleaned_no_ocr(monkeypatch):  # noqa: ANN001
    class FakePage:
        def __init__(self, t: str) -> None:
            self._t = t

        def extract_text(self) -> str:
            return self._t

    class FakeReader:
        def __init__(self, *a, **k) -> None:
            self.pages = [
                FakePage("第一页 两位数加法进位：个位相加满十，向十位进一。"),
                FakePage(
                    "义务教育教科书 数学 四年级 上册 "
                    "\uf000\uf001 OJOEE cmmmcmmmmmcmm"
                ),
            ]

    monkeypatch.setattr("pypdf.PdfReader", FakeReader)
    # 两页都有真实文字，不得触发 OCR
    monkeypatch.setattr(
        "app.features.materials.parser._rasterize_and_ocr", lambda *a, **k: {}
    )
    rep = parse_material(filename="数学四年级上册.pdf", data=b"%PDF-1.4 fake")
    assert isinstance(rep, ParseReport)
    assert "两位数加法进位" in rep.text
    assert "四年级" in rep.text
    assert "\uf000" not in rep.text
    assert rep.cleaned_chars > 0
    assert rep.ocr_pages == 0
    assert any("乱码" in w for w in rep.warnings)


def test_pdf_scan_page_triggers_ocr(monkeypatch):
    class FakePage:
        def __init__(self, t: str) -> None:
            self._t = t

        def extract_text(self) -> str:
            return self._t

    class FakeReader:
        def __init__(self, *a, **k) -> None:
            # 第 0 页有文字；第 1 页抽不出字 → 扫描页
            self.pages = [
                FakePage("这是一页正常文字内容，足够长不会被判定为扫描。"),
                FakePage(""),
            ]

    monkeypatch.setattr("pypdf.PdfReader", FakeReader)
    monkeypatch.setattr(
        "app.features.materials.parser._rasterize_and_ocr",
        lambda data, idxs: {1: "扫描页 OCR 识别出的数学公式与例题"},
    )
    rep = parse_material(filename="scan.pdf", data=b"%PDF-1.4 fake")
    assert rep.scan_pages == 1
    assert rep.ocr_pages == 1
    assert "扫描页 OCR 识别出的数学公式与例题" in rep.text
    assert any("已自动 OCR" in w for w in rep.warnings)


def test_pdf_scan_page_without_ocr_engine_warns(monkeypatch):
    class FakePage:
        def __init__(self, t: str) -> None:
            self._t = t

        def extract_text(self) -> str:
            return self._t

    class FakeReader:
        def __init__(self, *a, **k) -> None:
            # 第 0 页正常文字（保证整篇非空，不至于触发空文本异常）；第 1 页抽不出字
            self.pages = [
                FakePage("这是一页正常文字内容，足够长不会被判定为扫描页。"),
                FakePage(""),
            ]

    monkeypatch.setattr("pypdf.PdfReader", FakeReader)
    # 模拟 OCR 引擎缺失：返回空
    monkeypatch.setattr(
        "app.features.materials.parser._rasterize_and_ocr", lambda data, idxs: {}
    )
    rep = parse_material(filename="scan.pdf", data=b"%PDF-1.4 fake")
    assert rep.scan_pages == 1
    assert rep.ocr_pages == 0
    assert any("OCR 组件未安装" in w or "未能识别" in w for w in rep.warnings)


def test_empty_text_after_cleaning_raises(monkeypatch):  # noqa: ANN001
    class FakePage:
        def extract_text(self) -> str:
            return "\uf000\uf001 cmmmcmm"  # 全是噪声，清洗后为空

    class FakeReader:
        def __init__(self, *a, **k) -> None:
            self.pages = [FakePage()]

    monkeypatch.setattr("pypdf.PdfReader", FakeReader)
    monkeypatch.setattr(
        "app.features.materials.parser._rasterize_and_ocr", lambda *a, **k: {}
    )
    with pytest.raises(ParseError):
        parse_material(filename="empty.pdf", data=b"%PDF-1.4 fake")
