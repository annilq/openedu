#!/usr/bin/env python3
"""教材版权合规检测门禁（ADR-0019 决策 5）。

扫描「对外分发产物」中的题目内容，判断是否对受版权保护的教材构成**实质性复制**
（章节结构雷同 / 例题原文重合度超阈值）。命中即阻断发布（退出码 1），须人工复核放行。

设计原则
--------
- 纯标准库，CI 无需装额外依赖；不依赖业务代码，可独立运行。
- 受保护语料（protected corpus）由法务/合规基于「公版或已授权」教材填充，**本脚本不内置
  任何受版权保护的原文**（见 `protected_corpus/README.md`）。
- 相似度用「归一化文本 → 字符 n-gram → Jaccard 重叠」衡量，对中文题干/讲解稳健，且无外部
  模型依赖。阈值可调（`--threshold`，默认 0.5）。
- 同时做「结构雷同」检查：内容若连续命中受保护语料的多段（疑似整章照搬），单独计为结构命中。

用法
----
  扫描题库（SQLite）：
    python copyright_compliance_check.py --db path/to/app.db \
        --protected protected_corpus/ --threshold 0.5 --report report.json

  扫描导出的 JSON 内容（CI 用，题库经 `uv run` 命令导出后传此）：
    python copyright_compliance_check.py --json content.json \
        --protected protected_corpus/

  离线自测（不依赖任何外部数据，验证门禁逻辑本身）：
    python copyright_compliance_check.py --self-test

退出码
------
  0 = 未发现实质性复制（可发布）
  1 = 命中（阻断发布，report 列出明细）
  2 = 配置/运行错误（如语料缺失且未显式跳过）
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import unicodedata
from dataclasses import dataclass, asdict
from typing import Iterable


# —— 文本归一化与相似度 ——

_CJK = r"\u4e00-\u9fff"
# 保留：字母数字 + 中日韩汉字；去掉空白与标点，避免格式差异干扰。
_KEEP = re.compile(rf"[^\w{_CJK}]")


def normalize(text: str | None) -> str:
    """小写 + Unicode 归一化 + 去空白/标点，得到可比较的字符序列。"""
    if not text:
        return ""
    text = unicodedata.normalize("NFKC", text)
    text = text.lower()
    text = _KEEP.sub("", text)
    return text


def shingles(text: str, n: int = 4) -> frozenset[str]:
    """字符 n-gram 集合。短于 n 的文本整体作为 1 个 shingle。"""
    s = normalize(text)
    if len(s) < n:
        return frozenset({s}) if s else frozenset()
    return frozenset(s[i : i + n] for i in range(len(s) - n + 1))


def jaccard(a: frozenset[str], b: frozenset[str]) -> float:
    if not a or not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union if union else 0.0


# —— 数据模型 ——

@dataclass
class ContentItem:
    """待检测的一条内容（通常对应一道题的拼接文本）。"""

    id: str
    text: str
    meta: dict = None  # type: ignore[assignment]

    def to_dict(self) -> dict:
        d = asdict(self)
        d["meta"] = self.meta or {}
        return d


@dataclass
class Flag:
    item_id: str
    score: float
    matched_corpus: str
    reason: str

    def to_dict(self) -> dict:
        return asdict(self)


# —— 语料与内容加载 ——

def load_protected_corpus(path: str) -> list[tuple[str, str]]:
    """读取受保护语料，返回 [(来源名, 文本), ...]。

    `path` 可为文件或目录：
      - 文件：整文件作为一段受保护文本。
      - 目录：递归读取所有 `.txt` / `.md`，每个文件一段；文件名作为来源名。
    """
    items: list[tuple[str, str]] = []
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as fh:
            items.append((os.path.basename(path), fh.read()))
        return items
    if os.path.isdir(path):
        for root, _dirs, files in os.walk(path):
            for name in sorted(files):
                if name.endswith((".txt", ".md")):
                    full = os.path.join(root, name)
                    with open(full, "r", encoding="utf-8") as fh:
                        items.append((name, fh.read()))
        return items
    raise FileNotFoundError(f"受保护语料路径不存在：{path}")


def load_from_db(db_path: str) -> list[ContentItem]:
    """从 SQLite 的 `questions` 表抽取待检测内容。"""
    cols = ["knowledge_point", "stem", "answer", "explanation"]
    items: list[ContentItem] = []
    con = sqlite3.connect(db_path)
    try:
        con.row_factory = sqlite3.Row
        cur = con.execute(
            "SELECT id, knowledge_point, stem, answer, explanation FROM questions"
        )
        for r in cur.fetchall():
            parts = [r[c] for c in cols if r[c]]
            if not parts:
                continue
            items.append(
                ContentItem(
                    id=str(r["id"]),
                    text=" | ".join(parts),
                    meta={c: r[c] for c in cols},
                )
            )
    finally:
        con.close()
    return items


def load_from_json(json_path: str) -> list[ContentItem]:
    """从 JSON 读取待检测内容：可为字符串列表，或 [{id, text}|{id, ...字段}]。"""
    with open(json_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    items: list[ContentItem] = []
    for i, entry in enumerate(data):
        if isinstance(entry, str):
            items.append(ContentItem(id=f"item-{i}", text=entry))
        else:
            text = entry.get("text") or " | ".join(
                str(v) for v in entry.values() if isinstance(v, str)
            )
            items.append(ContentItem(id=str(entry.get("id", f"item-{i}")), text=text))
    return items


# —— 核心检测 ——

def scan_item(item: ContentItem, corpus: list[tuple[str, str]], threshold: float) -> Flag | None:
    """对单条内容计算与受保护语料的最大重合度；超阈值返回 Flag。"""
    grams = shingles(item.text)
    if not grams:
        return None
    best_score = 0.0
    best_src = ""
    hits = 0  # 命中段数（结构雷同信号）
    for src, text in corpus:
        score = jaccard(grams, shingles(text))
        if score >= threshold:
            hits += 1
        if score > best_score:
            best_score = score
            best_src = src
    if best_score >= threshold:
        reason = "例题原文重合度超阈值"
        if hits >= 3:
            reason = f"疑似整章/多段照搬（命中 {hits} 段）+ 原文重合度超阈值"
        return Flag(item.id, round(best_score, 3), best_src, reason)
    return None


def run_scan(
    items: list[ContentItem],
    corpus: list[tuple[str, str]],
    threshold: float,
) -> list[Flag]:
    flags: list[Flag] = []
    for item in items:
        flag = scan_item(item, corpus, threshold)
        if flag:
            flags.append(flag)
    return flags


# —— 自测（离线，不依赖外部数据） ——

def self_test() -> int:
    """内置演示：识别实质性复制（阻断）+ 放过清洁内容（通过）。"""
    protected = [
        (
            "math-3b-ch4",
            "把一个蛋糕平均分成四份取其中的一份就是四分之一分数表示成四分之一",
        ),
    ]
    copied = ContentItem(
        "copied-1",
        "把一个蛋糕平均分成四份取其中的一份就是四分之一",  # 与受保护段高度重合
    )
    clean = ContentItem(
        "clean-1",
        "小明有五颗糖要分给两个小朋友每人能分到几颗请用加法列算式计算",  # 完全不同主题
    )
    flags = run_scan([copied, clean], protected, threshold=0.5)
    flagged_ids = {f.item_id for f in flags}
    ok = ("copied-1" in flagged_ids) and ("clean-1" not in flagged_ids)
    print("[self-test] 受保护语料命中 copied-1 且放行 clean-1：", "PASS" if ok else "FAIL")
    if not ok:
        for f in flags:
            print("  flagged:", f.to_dict())
    return 0 if ok else 1


# —— CLI ——

def build_argparser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="教材版权合规检测门禁（ADR-0019）")
    p.add_argument("--db", help="SQLite 题库路径（questions 表）")
    p.add_argument("--json", help="JSON 内容路径（字符串列表或对象列表）")
    p.add_argument("--protected", required=False, help="受保护语料文件/目录")
    p.add_argument("--threshold", type=float, default=0.5, help="重合度阈值（默认 0.5）")
    p.add_argument("--report", help="输出 JSON 报告路径")
    p.add_argument(
        "--skip-if-no-corpus",
        action="store_true",
        help="受保护语料缺失时退出 0（仅警告），用于骨架期 CI 不误阻断",
    )
    p.add_argument("--self-test", action="store_true", help="离线自测门禁逻辑")
    return p


def main(argv: Iterable[str] | None = None) -> int:
    args = build_argparser().parse_args(argv)

    if args.self_test:
        return self_test()

    # 加载待检测内容
    items: list[ContentItem] = []
    if args.db:
        items = load_from_db(args.db)
    elif args.json:
        items = load_from_json(args.json)
    else:
        print("错误：须指定 --db 或 --json 提供待检测内容", file=sys.stderr)
        return 2

    if not items:
        print("无待检测内容，门禁通过。")
        return 0

    # 加载受保护语料
    if not args.protected:
        msg = "未指定 --protected 受保护语料"
        if args.skip_if_no_corpus:
            print(f"[warn] {msg}：按 --skip-if-no-corpus 放行（骨架期）。")
            return 0
        print(f"错误：{msg}", file=sys.stderr)
        return 2
    try:
        corpus = load_protected_corpus(args.protected)
    except FileNotFoundError as e:
        if args.skip_if_no_corpus:
            print(f"[warn] {e}：按 --skip-if-no-corpus 放行（骨架期）。")
            return 0
        print(f"错误：{e}", file=sys.stderr)
        return 2

    if not corpus:
        print(f"[warn] 受保护语料为空（{args.protected}），门禁放行（无参照）。")
        return 0

    # 检测
    flags = run_scan(items, corpus, args.threshold)
    report = {
        "threshold": args.threshold,
        "scanned": len(items),
        "corpus_segments": len(corpus),
        "blocked": bool(flags),
        "flags": [f.to_dict() for f in flags],
    }
    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            json.dump(report, fh, ensure_ascii=False, indent=2)

    if flags:
        print(f"[BLOCK] 命中 {len(flags)} 条实质性复制，阻断发布：")
        for f in flags:
            print(f"  - {f.item_id}  score={f.score}  src={f.matched_corpus}  ({f.reason})")
        return 1

    print(f"[PASS] 扫描 {len(items)} 条内容，未命中受保护教材实质性复制。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
