"""切片器（ADR-0055 §5）：整篇文本 → 检索片段。

策略刻意朴素（段落聚合 + 目标长度 + 少量 overlap）：版本号 ``CHUNKER_VERSION``
随策略一起走——改这里的逻辑必须递增版本，否则存量向量与新查询不同空间
（stale 机制依赖这个纪律）。效果调优等 B7 黄金集有了 Recall@5 基线再说，
现在拍脑袋调参数是负资产。
"""

from __future__ import annotations

import re

from app.db.models import CHUNKER_VERSION

# 目标片段长度（字符）：512 是中文教材场景的常用起点（B7 会用黄金集校准）
_TARGET_CHARS = 512
# 相邻片段重叠：给跨片段的句子留 10% 上下文
_OVERLAP_CHARS = 50

_PARA_SPLIT = re.compile(r"\n\s*\n+")


def chunk_text(text: str) -> list[str]:
    """段落聚合切片：段落拼接逼近目标长度；超长单段按句子再切。"""
    paragraphs = [p.strip() for p in _PARA_SPLIT.split(text) if p.strip()]
    if not paragraphs:
        return []
    chunks: list[str] = []
    buf = ""
    for para in paragraphs:
        # 超长段落先按句子切成目标长度的小块，再进聚合
        if len(para) > _TARGET_CHARS:
            if buf:
                chunks.append(buf)
                buf = ""
            chunks.extend(_split_long(para))
            continue
        if buf and len(buf) + len(para) + 1 > _TARGET_CHARS:
            chunks.append(buf)
            tail = buf[-_OVERLAP_CHARS:] if _OVERLAP_CHARS else ""
            buf = (tail + "\n" + para).strip() if tail else para
        else:
            buf = f"{buf}\n{para}".strip()
    if buf:
        chunks.append(buf)
    return chunks


def _split_long(para: str) -> list[str]:
    """超长段落按句边界切到目标长度（带 overlap）。"""
    sentences = re.split(r"(?<=[。！？!?.；;])\s*", para)
    pieces: list[str] = []
    buf = ""
    for s in sentences:
        if not s:
            continue
        if buf and len(buf) + len(s) > _TARGET_CHARS:
            pieces.append(buf)
            buf = buf[-_OVERLAP_CHARS:] + s if _OVERLAP_CHARS else s
        else:
            buf += s
    if buf:
        pieces.append(buf)
    return pieces


__all__ = ["chunk_text", "CHUNKER_VERSION"]
