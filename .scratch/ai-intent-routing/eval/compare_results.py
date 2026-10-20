"""对比两个评测结果 JSON 里的变体（逐用例 + 生产有效准确率）。

用法::

    python compare_results.py results-A.json "变体名1" results-B.json "变体名2"

「生产有效准确率」= 门控采纳且正确 / 计分用例数：不采纳的用例在生产里落能力引导，
对用户而言不算「路由对了」，故这个指标比 top-1 更贴近真实体感。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def load(path: str, name: str) -> list[dict]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    for key, rows in data.items():
        if key.endswith(f"#{name}"):
            return rows
    raise SystemExit(f"未找到变体 {name!r}；可用：{[k for k in data if '#' in k]}")


def cell(r: dict) -> str:
    p = r["pmax"]
    got = f"{r['choice']}@{p:.2f}" if isinstance(p, float) else str(r["choice"])
    if not r["scored"]:
        return got + " ·"
    return got + (" ✓" if r["choice"] == r["expect"] else " ✗")


def effective(rows: list[dict]) -> tuple[int, int, float]:
    scored = [r for r in rows if r["scored"]]
    adopted = [r for r in scored if isinstance(r["pmax"], float) and r["pmax"] >= 0.5]
    ok = sum(1 for r in adopted if r["choice"] == r["expect"])
    return ok, len(scored), ok / len(scored) if scored else 0.0


def main() -> int:
    pa, na, pb, nb = sys.argv[1:5]
    a, b = load(pa, na), load(pb, nb)
    print(f"{'用例':<22}{'期望':<12}{na:<20}{nb:<20}")
    for ra, rb in zip(a, b):
        mark = "" if ra["scored"] and ra["choice"] == ra["expect"] == rb.get("choice") else "*"
        print(f"{ra['case']:<22}{str(ra['expect']):<12}{cell(ra):<20}{cell(rb):<20}{mark}")
    for name, rows in ((na, a), (nb, b)):
        ok, total, ratio = effective(rows)
        hits = sum(1 for r in rows if r["scored"] and r["choice"] == r["expect"])
        bad = sum(
            1
            for r in rows
            if r["scored"] and isinstance(r["pmax"], float) and r["pmax"] >= 0.8
            and r["choice"] != r["expect"]
        )
        print(f"\n{name}: top-1 {hits}/{total} = {hits / total:.0%} · 生产有效 {ok}/{total} = {ratio:.0%} · 高置信错误 {bad}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
