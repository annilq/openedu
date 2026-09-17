"""打印导出的中文字体依赖（ADR-0052 决策：字体由配置指定 + 启动冒烟校验）。

字体这块有三个坑，都踩过：

1. **编码问题** vs **字体缺失** 是两件事。前者表现为乱码，后者表现为豆腐块；
   两者对家长都是「打印了一堆废纸」，所以必须在**启动期**就暴露，而不是等导出时。
2. ``frontend/assets/fonts/NotoSansSC.ttf`` 是**可变字体且默认实例 Thin**，
   Typst 不会按目标字重实例化它 → 直接拿来排版，纸上是细笔画。
   静态 Regular 的生成见 ``scripts/build_export_font.py``。
3. 只能指定**目录**不能指定文件（Typst 的 ``font_paths``），所以这里校验的是
   「目录存在且里面有字体文件」，而不是某个具体文件名。
"""
from __future__ import annotations

import logging
from pathlib import Path

from app.core.config import settings
from app.core.errors import AppErrorException, ErrCode

logger = logging.getLogger(__name__)

_FONT_SUFFIXES = (".ttf", ".otf", ".ttc", ".otc")


def font_dir() -> Path:
    raw = (settings.EXPORT_FONT_DIR or "").strip()
    return Path(raw) if raw else Path()


def font_files() -> list[Path]:
    directory = font_dir()
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.iterdir() if p.suffix.lower() in _FONT_SUFFIXES)


def font_available() -> bool:
    return bool(font_files())


def check_export_font_health() -> None:
    """启动冒烟：字体缺失要尽早暴露。

    沿用 ADR-0041（`check_runtime_secrets_health`）的同一套口径：
    生产环境缺配直接阻断启动，开发环境只告警——本地克隆起来没字体不该崩，
    但部署出去没字体一定是运维事故。
    """
    directory = font_dir()
    if font_available():
        return
    message = (
        f"打印导出的中文字体目录不可用：{directory}（配置 EXPORT_FONT_DIR）。"
        "缺少中文字体时导出会产出豆腐块，已拒绝提供打印导出。"
        "生成静态 Regular 字体请运行 scripts/build_export_font.py。"
    )
    if settings.FASTAPI_ENV == "production":
        raise RuntimeError(message)
    logger.warning(message)


def require_font_dir() -> Path:
    """取字体目录；不可用则抛 ``503``，由前端如实告诉家长「服务端没配好」。"""
    if not font_available():
        raise AppErrorException(
            ErrCode.EXPORT_FONT_MISSING,
            "打印导出的中文字体未配置，暂时无法导出，请联系管理员",
        )
    return font_dir()
