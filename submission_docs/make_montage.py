#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把演示录屏截帧拼成「各主要功能模块界面」一张图（3 列 × 2 行，带中文标签）。

输入：figures/ 下的 raw_XX.png 截帧（由 ffmpeg 从 raw/demo_NN.mov 抽取）。
输出：figures/fig_modules.png
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FIG = HERE / "figures"

TILES = [
    ("raw_02.png", "AI 模型管理"),
    ("raw_04.png", "资料库与知识点"),
    ("raw_06.png", "课件演示·交互图形"),
    ("raw_08.png", "AI 流式出题"),
    ("raw_11_t3.0.png", "学生端首页"),
    ("raw_13.png", "掌握度"),
]

TILE_W = 760      # 单格缩放后的宽
LABEL_H = 56      # 标签条高
GAP = 16
COLS = 3
BG = (250, 247, 240)
LABEL_BG = (232, 228, 218)
LABEL_FG = (40, 40, 40)

FONT_CANDIDATES = [
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def main():
    font = load_font(30)
    # 统一按 TILE_W 等比缩放，行高取该行最大值
    tiles = []
    for fname, label in TILES:
        img = Image.open(FIG / fname).convert("RGB")
        h = round(img.height * TILE_W / img.width)
        tiles.append((img.resize((TILE_W, h), Image.LANCZOS), label))

    rows = [tiles[i:i + COLS] for i in range(0, len(tiles), COLS)]
    col_w = TILE_W
    row_hs = [max(t[0].height for t in row) + LABEL_H for row in rows]

    W = COLS * col_w + (COLS + 1) * GAP
    H = sum(row_hs) + (len(rows) + 1) * GAP
    canvas = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(canvas)

    y = GAP
    for row, rh in zip(rows, row_hs):
        x = GAP
        for img, label in row:
            # 标签条
            draw.rectangle([x, y, x + col_w, y + LABEL_H], fill=LABEL_BG)
            bbox = draw.textbbox((0, 0), label, font=font)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            draw.text((x + (col_w - tw) // 2, y + (LABEL_H - th) // 2 - bbox[1]),
                      label, font=font, fill=LABEL_FG)
            # 截图（垂直方向贴标签条下方居中）
            ty = y + LABEL_H + (rh - LABEL_H - img.height) // 2
            canvas.paste(img, (x, ty))
            x += col_w + GAP
        y += rh + GAP

    out = FIG / "fig_modules.png"
    canvas.save(out)
    print(f"wrote {out}  {canvas.size[0]}x{canvas.size[1]}")


if __name__ == "__main__":
    main()
