"""生成打印导出用的**静态 Regular 中文字体**（一次性，产物已入库）。

背景（这是踩过才知道的坑）：
``frontend/assets/fonts/NotoSansSC.ttf`` 是一份**可变字体**，且它的默认实例是
``wght=100``（Thin）。Typst 目前不会按目标字重去实例化可变字体轴，于是
``#set text(font: "Noto Sans SC", weight: 400)`` 拿到的仍然是 Thin——
放到题目卷子打印出来笔画极细，给 K12 的纸面材料不可用。

对策：用 fontTools 把可变字体**钉死在 wght=400** 生成一份静态字体，
 Typst 侧拿到的是货真价实的 Regular。

用法::

    uv run python scripts/build_export_font.py

依赖仅构建期需要 ``fonttools``（不进运行时依赖表）：::

    uv run --with fonttools python scripts/build_export_font.py
"""
from __future__ import annotations

import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
SOURCE = BACKEND_DIR.parent / "frontend" / "assets" / "fonts" / "NotoSansSC.ttf"
TARGET = BACKEND_DIR / "assets" / "fonts" / "NotoSansSC-Regular.ttf"
TARGET_WEIGHT = 400


def main() -> int:
    if not SOURCE.exists():
        print(f"源字体不存在：{SOURCE}", file=sys.stderr)
        return 1
    try:
        from fontTools.ttLib import TTFont  # noqa: PLC0415
        from fontTools.varLib import instancer  # noqa: PLC0415
    except ImportError:
        print(
            "缺少 fonttools，请用：uv run --with fonttools python scripts/build_export_font.py",
            file=sys.stderr,
        )
        return 2

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    font = TTFont(SOURCE)
    if "fvar" not in font:
        print("源字体不是可变字体，直接复制", file=sys.stderr)
        TARGET.write_bytes(SOURCE.read_bytes())
        return 0
    pinned = instancer.instantiateVariableFont(
        font,
        {"wght": TARGET_WEIGHT},
        inplace=True,
        optimize=True,
        # 必须开：不开的话 name 表里仍写着 "Noto Sans SC Thin"（nameID 1）
        # 与 "Thin"（typographic subfamily），Typst 会把它当成 Thin 注册，
        # 纸面依旧是细笔画。开了之后 nameID 1/2 才会变成 "Noto Sans SC" / "Regular"。
        updateFontNames=True,
    )
    pinned.save(TARGET)
    print(f"已生成 {TARGET}（{TARGET.stat().st_size // 1024} KB）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
