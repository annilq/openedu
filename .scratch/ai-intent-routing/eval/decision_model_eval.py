"""决策模型本地影子评测（记忆 §8：路由取舍必须由本项目中文数据说话）。

用本项目**生产链路的同一份输入**去问 ollaya 上的候选决策模型——不是「像生产那样」
的复刻，而是直接 import 生产的构件：

- ``criteria``  = ``agent_core.router._capability_text`` 对真实 manifest 的投影
  （改 manifest 文案立刻反映到评测里，不存在手抄副本漂移）
- 可见集        = ``AgentRuntime.visible_businesses(role)``（不是硬编码的业务列表——
  2026-10-21 修正：旧脚本把学生端写成 K=2，生产实为 K=3，tasks 对学生可见）
- ``state``     = ``agent_core.router._build_routing_state`` 的产物（近 12 轮 + 当前消息追尾）
- ``INSTRUCTIONS`` = 适配器的 ``_ROUTING_INSTRUCTIONS``

评测四件事：中文 top-1 准确率、**门控用的 pmax**（不是 TypeSafe 的 confidence）、
延迟、以及长历史是否触发 ``422 STATE_TRUNCATED``。并额外给出「门控后」视角：
pmax < 0.5 的用例在生产里不采纳 → 落能力引导。

用法（ollaya 需在 127.0.0.1:11435 运行；须用 backend 的 venv 跑以便 import 本项目）：:

    cd <repo>/backend
    .venv/bin/python ../.scratch/ai-intent-routing/eval/decision_model_eval.py
    .venv/bin/python .../decision_model_eval.py --models largha
    .venv/bin/python .../decision_model_eval.py --json ../.scratch/ai-intent-routing/eval/results-X.json

只依赖标准库 + 本项目；显式绕过系统代理（macOS 代理会把 localhost 请求也吞掉）。
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
import urllib.error
import urllib.request
from dataclasses import replace
from pathlib import Path

# backend 根目录（本文件位于 <repo>/.scratch/ai-intent-routing/eval/）
BACKEND = Path(__file__).resolve().parents[3] / "backend"
sys.path.insert(0, str(BACKEND))

from agent_core.adapters.laya import _ROUTING_INSTRUCTIONS  # noqa: E402
from agent_core.registry import discover_subagent_manifests  # noqa: E402
from agent_core.router import _build_routing_state, _capability_text  # noqa: E402
from agent_core.runtime import AgentRuntime  # noqa: E402

HOST = "http://127.0.0.1:11435"
DEFAULT_MODELS = ["laya:multilingual"]
THRESHOLD = 0.5  # 与 LayaDecisionModel 的默认门控一致

INSTRUCTIONS = _ROUTING_INSTRUCTIONS
_QUESTION_ID = "business"

_MANIFESTS = discover_subagent_manifests()
_RUNTIME = AgentRuntime(_MANIFESTS)


def criteria_for(role: str) -> dict[str, str]:
    """生产同款候选：可见集取自 runtime，文案取自 ``_capability_text``。"""
    return {b: _capability_text(_MANIFESTS[b]) for b in _RUNTIME.visible_businesses(role)}


# (用例 id, 角色, 期望业务或 None=不计分, 当前消息, 历史轮次, 来源)
# 来源：trace=真实事故形状；构造=同义改写/近邻
CASES: list[tuple[str, str, str | None, str, list[tuple[str, str]] | None, str]] = [
    # ── 教师 · 查数据（tasks）──
    ("T01 查学生名单", "teacher", "tasks", "我班有哪些学生", None, "trace"),
    ("T02 查学习进度", "teacher", "tasks", "我班学生的学习进度怎么样", None, "构造"),
    ("T03 查人数", "teacher", "tasks", "我们班一共有多少人", None, "构造"),
    ("T04 查错题", "teacher", "tasks", "我的错题有哪些", None, "trace"),
    ("T05 查错题变体", "teacher", "tasks", "我最近做错了哪些题", None, "构造"),
    ("T06 待复习", "teacher", "tasks", "我需要复习哪些知识点", None, "构造"),
    ("T07 查作业", "teacher", "tasks", "今天布置了什么作业", None, "构造"),
    # ── 教师 · 出题（tasks）──
    ("T08 首轮出题", "teacher", "tasks", "帮我出 2 道四年级数学题", None, "trace"),
    ("T09 出一道", "teacher", "tasks", "出一道四年级数学题", None, "trace"),
    ("T10 来一道", "teacher", "tasks", "来一道三年级分数的题", None, "trace"),
    ("T11 出 5 道", "teacher", "tasks", "出 5 道二年级加减法", None, "构造"),
    (
        "T12 续接改年级",
        "teacher",
        "tasks",
        "数学",
        [("user", "帮我出 2 道四年级数学题"), ("assistant", "好的，这是两道四年级数学题…")],
        "trace",
    ),
    (
        "T13 续接换学科",
        "teacher",
        "tasks",
        "换成四年级的分数题",
        [("user", "帮我出 2 道五年级数学题"), ("assistant", "好的，这是两道五年级数学题…")],
        "trace",
    ),
    (
        "T14 续接加量",
        "teacher",
        "tasks",
        "再来两道",
        [("user", "帮我出 2 道四年级数学题"), ("assistant", "好的：① 24×15=？ ② 3.6+2.75=？")],
        "构造",
    ),
    # ── 教师 · 讲解（tutor）──
    ("T15 讲解选择题", "teacher", "tutor", "这道题为什么选 B", None, "trace"),
    ("T16 讲解解法", "teacher", "tutor", "这道题的解法是什么", None, "构造"),
    ("T17 讲解答案", "teacher", "tutor", "为什么答案是 12", None, "构造"),
    ("T18 讲解公式", "teacher", "tutor", "这个公式我不懂，讲一下", None, "构造"),
    (
        "T19 续接转讲解",
        "teacher",
        "tutor",
        "第一题怎么算的？",
        [("user", "帮我出 2 道四年级数学题"), ("assistant", "好的：① 24×15=？ ② 3.6+2.75=？")],
        "trace",
    ),
    (
        "T20 续接问答案",
        "teacher",
        "tutor",
        "第三题的答案是多少",
        [("user", "帮我出 3 道分数加减法"), ("assistant", "好的，这是三道分数题…")],
        "构造",
    ),
    ("T21 概念提问", "teacher", "tutor", "什么是分数", None, "构造"),
    (
        "T22 续接保持讲解",
        "teacher",
        "tutor",
        "再讲一遍",
        [("user", "什么是分数"), ("assistant", "分数表示整体的一部分…")],
        "构造",
    ),
    # ── 教师 · 元问题（capability）──
    ("T23 你能做什么", "teacher", "capability", "你能做什么", None, "trace"),
    ("T24 你会什么", "teacher", "capability", "你会什么", None, "构造"),
    ("T25 你能帮我干什么", "teacher", "capability", "你能帮我干什么", None, "构造"),
    # ── 学生（可见集与教师相同：tasks 对学生可见，写工具才按角色拒绝）──
    ("S01 算术求解", "student", "tutor", "23 + 45 怎么算", None, "trace"),
    ("S02 分数求解", "student", "tutor", "1/2 + 1/3 等于多少", None, "构造"),
    ("S03 概念提问", "student", "tutor", "什么是分数", None, "构造"),
    ("S04 作答求证", "student", "tutor", "这道题我选 C 对吗", None, "构造"),
    (
        "S05 续接追问",
        "student",
        "tutor",
        "还是不懂",
        [("user", "什么是分数"), ("assistant", "分数表示整体的一部分…")],
        "trace",
    ),
    ("S06 元问题", "student", "capability", "你能帮我做什么", None, "trace"),
    ("S07 元问题变体", "student", "capability", "你都会些什么", None, "构造"),
    ("S08 查自己的错题", "student", "tasks", "我的错题有哪些", None, "构造"),
    ("S09 查自己的作业", "student", "tasks", "我今天要做什么作业", None, "构造"),
    # ── 模糊句：不计分，只观察 pmax 是否诚实（低于阈值=安全回落能力引导）──
    ("X01 闲聊", "teacher", None, "随便聊聊", None, "构造"),
    ("X02 空泛", "teacher", None, "你好呀", None, "构造"),
    ("X03 学生出题", "student", None, "帮我出几道题练练", None, "构造"),
]


# 留出验证集：写于选型**之后**、只用于最终裁决，不参与任何一轮文案选择
# （多轮爬山会把文案调到调优集上，留出集是唯一能看出「真的涨了」还是「背下来了」的尺子）
HOLDOUT_CASES: list[tuple[str, str, str | None, str, list[tuple[str, str]] | None, str]] = [
    ("H01 谁进度落后", "teacher", "tasks", "这周谁的学习进度落后了", None, "留出"),
    ("H02 再出一份", "teacher", "tasks", "把上次那套题再出一份", None, "留出"),
    ("H03 掌握度", "teacher", "tasks", "这个知识点学生掌握得怎么样", None, "留出"),
    ("H04 通分", "teacher", "tutor", "为什么这个分数要先通分", None, "留出"),
    ("H05 看不懂算式", "teacher", "tutor", "我不明白这个算式", None, "留出"),
    ("H06 你会出题吗", "teacher", "capability", "你会出题吗", None, "留出"),
    ("H07 这道题怎么做", "student", "tutor", "这道题怎么做", None, "留出"),
    ("H08 乘法求解", "student", "tutor", "12 × 15 等于几", None, "留出"),
    ("H09 我错在哪", "student", "tutor", "我错在哪了", None, "留出"),
    ("H10 看我哪题错了", "student", "tasks", "帮我看看我哪题错了", None, "留出"),
]


def build_state(current: str, history: list[tuple[str, str]] | None) -> str:
    """复刻生产 state（直接调用 ``_build_routing_state``，history 形状一致）。"""
    turns = [{"role": r, "content": c} for r, c in (history or [])]
    return _build_routing_state(turns, current)


def long_state(turns: int = 12) -> str:
    """构造真实的 12 轮中文对话，用于实测上下文截断边界（ROUTING_HISTORY_LIMIT=12）。"""
    lines: list[str] = []
    for i in range(turns // 2):
        lines.append(f"user: 第{i + 1}单元的分数加减法我还是不太懂，能不能再讲一遍进位的地方")
        lines.append(
            f"assistant: 好的。以 {i + 1}/4 + {i + 2}/4 为例，分母相同直接把分子相加，"
            f"得到 {2 * i + 3}/4；超过 1 的部分写成带分数，这样你就能看出什么时候需要进位了。"
        )
    lines.append("user: 懂了，那再出几道类似的题练练手")
    return "\n".join(lines)


_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def ask(model: str, state: str, criteria: dict[str, str]) -> dict:
    """POST /v1/systemone（TypeSafe 兼容形状），返回评测记录行。"""
    payload = {
        "model": model,
        "state": state,
        "questions": {
            _QUESTION_ID: {
                "type": "choice",
                "instructions": INSTRUCTIONS,
                "criteria": criteria,
            }
        },
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{HOST}/v1/systemone",
        data=body,
        headers={"Content-Type": "application/json", "Authorization": "Bearer local"},
    )
    started = time.monotonic()
    try:
        with _opener.open(req, timeout=60.0) as resp:
            raw = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:  # 422 STATE_TRUNCATED 等非 2xx
        detail = exc.read().decode("utf-8", "replace")[:200]
        return {
            "latency_ms": int((time.monotonic() - started) * 1000),
            "error": f"HTTP {exc.code} {detail}",
            "choice": None,
            "pmax": None,
        }
    except Exception as exc:  # noqa: BLE001 — 评测脚本，任何失败都记录为错误
        return {
            "latency_ms": int((time.monotonic() - started) * 1000),
            "error": f"{type(exc).__name__}: {exc}",
            "choice": None,
            "pmax": None,
        }
    latency = int((time.monotonic() - started) * 1000)
    answer = (raw.get("answers") or {}).get(_QUESTION_ID) or {}
    probs = answer.get("probabilities") or {}
    pmax = max(probs.values()) if isinstance(probs, dict) and probs else None
    return {
        "latency_ms": latency,
        "error": None,
        "choice": answer.get("choice"),
        "pmax": pmax,
        "confidence": answer.get("confidence"),
        "probabilities": probs,
        "served_model": raw.get("model"),
    }


def criteria_for(role: str, override: dict[str, str] | None = None) -> dict[str, str]:
    """生产同款候选；``override`` 只替换 description（批量对比文案变体用）。"""
    out: dict[str, str] = {}
    for b in _RUNTIME.visible_businesses(role):
        m = _MANIFESTS[b]
        if override and b in override:
            m = replace(m, description=override[b])
        out[b] = _capability_text(m)
    return out


def run(
    models: list[str],
    show_probs: bool = False,
    variants: dict[str, dict[str, str]] | None = None,
) -> dict:
    results: dict[str, list[dict]] = {}
    for model in models:
        warm = ask(model, "user: 你好", criteria_for("teacher"))
        rows: list[dict] = []
        for case_id, role, expect, current, history, source in CASES:
            row = ask(model, build_state(current, history), criteria_for(role))
            row.update(
                case=case_id,
                role=role,
                expect=expect,
                scored=expect is not None,
                source=source,
                state_chars=len(build_state(current, history)),
            )
            rows.append(row)
            if show_probs:
                print(f"    {row.get('probabilities')}")
        long_row = ask(model, long_state(), criteria_for("teacher"))
        long_row.update(
            case="L00 长历史(12轮)",
            role="teacher",
            expect=None,
            source="构造",
            scored=False,
            state_chars=len(long_state()),
        )
        hold: list[dict] = []
        if not variants:
            for cid, role, exp, cur, hist, _src in HOLDOUT_CASES:
                row = ask(model, build_state(cur, hist), criteria_for(role))
                row.update(case=cid, role=role, expect=exp, scored=exp is not None, source="留出")
                hold.append(row)
            h = _summarize(hold)
            print(
                f"  留出验证集（未参与选型）：top-1 {h['hits']}/{h['scored']} = {h['acc']:.0%}"
                f" · 采纳且正确 {h['adopt_hits']}/{h['scored']}"
                f" · 高置信错误 {h['bad']}"
            )
        results[model] = rows
        results[f"{model}#long"] = [long_row]
        if hold:
            results[f"{model}@holdout"] = hold
        _print_model(model, rows, long_row, warm)

    # 文案变体批量对比：同一模型、同一用例集，只换 criteria 文本
    if variants:
        model = models[0]
        print(f"\n════ 文案变体对比（{model}）════")
        print(f"{'变体':<18}{'top-1':<12}{'门控后':<16}{'高置信错':<10}{'平均pmax':<10}{'p50':>6}")
        summaries: dict[str, dict] = {}
        for name, override in variants.items():
            rows = [
                ask(model, build_state(cur, hist), criteria_for(role, override))
                | {
                    "case": cid,
                    "role": role,
                    "expect": exp,
                    "scored": exp is not None,
                    "source": src,
                }
                for cid, role, exp, cur, hist, src in CASES
            ]
            hold = [
                ask(model, build_state(cur, hist), criteria_for(role, override))
                | {"case": cid, "role": role, "expect": exp, "scored": exp is not None}
                for cid, role, exp, cur, hist, _src in HOLDOUT_CASES
            ]
            results[f"{model}#{name}"] = rows
            results[f"{model}#{name}@holdout"] = hold
            s = _summarize(rows)
            h = _summarize(hold)
            summaries[name] = s
            print(
                f"{name:<18}{s['hits']}/{s['scored']} = {s['acc']:.0%}  "
                f"{s['adopt_hits']}/{s['adopted']}            {s['bad']:<10}"
                f"{s['pmax']:<10.3f}{s['p50']:>6.0f}"
                f"  留出 {h['hits']}/{h['scored']} = {h['acc']:.0%}"
                f"（有效 {h['adopt_hits']}/{h['scored']}）"
            )
            for r in rows:
                if r["scored"] and r["choice"] != r["expect"]:
                    p = r["pmax"]
                    print(f"      ✗ {r['case']:<20} 期望 {r['expect']:<11} 实得 {r['choice']:<11}"
                          f"{p:.2f}" if isinstance(p, float) else "")
        return results
    return results


def _summarize(rows: list[dict]) -> dict:
    scored = [r for r in rows if r["scored"]]
    hits = sum(1 for r in scored if r["choice"] == r["expect"])
    adopted = [r for r in scored if isinstance(r["pmax"], float) and r["pmax"] >= THRESHOLD]
    pm = [r["pmax"] for r in scored if isinstance(r["pmax"], float)]
    bad = [
        r for r in scored
        if isinstance(r["pmax"], float) and r["pmax"] >= 0.8 and r["choice"] != r["expect"]
    ]
    return {
        "hits": hits,
        "scored": len(scored),
        "acc": hits / len(scored) if scored else 0.0,
        "adopted": len(adopted),
        "adopt_hits": sum(1 for r in adopted if r["choice"] == r["expect"]),
        "bad": len(bad),
        "pmax": statistics.fmean(pm) if pm else float("nan"),
        "p50": statistics.median([r["latency_ms"] for r in rows]),
    }


def _print_model(model: str, rows: list[dict], long_row: dict, warm: dict) -> None:
    print(f"\n══ {model}（预热 {warm['latency_ms']} ms）══")
    print(f"{'用例':<22}{'期望':<12}{'实得':<12}{'判':<4}{'pmax':<8}{'门控':<8}{'ms':>6}  备注")
    scored = [r for r in rows if r["scored"]]
    for r in rows:
        mark = "" if not r["scored"] else ("✓" if r["choice"] == r["expect"] else "✗")
        p = r.get("pmax")
        p_s = f"{p:.3f}" if isinstance(p, (int, float)) else "—"
        gate = "" if not isinstance(p, (int, float)) else ("采纳" if p >= THRESHOLD else "不纳")
        note = (r["error"] or "")[:50]
        if not r["scored"]:
            note = "不计分· " + note
        print(
            f"{r['case']:<22}{r['expect'] or '—':<12}{r['choice'] or '—':<12}{mark:<4}"
            f"{p_s:<8}{gate:<8}{r['latency_ms']:>6}  {note}"
        )
    ln = long_row
    print(
        f"{'长历史 12 轮':<22}{'—':<12}{ln['choice'] or '—':<12}{'—':<4}"
        f"{'—':<8}{'—':<8}{ln['latency_ms']:>6}  {(ln['error'] or '不截断')[:50]}"
    )
    hits = sum(1 for r in scored if r["choice"] == r["expect"])
    lats = [r["latency_ms"] for r in rows]
    pm = [r["pmax"] for r in scored if isinstance(r["pmax"], (int, float))]
    adopted = [r for r in scored if isinstance(r["pmax"], (int, float)) and r["pmax"] >= THRESHOLD]
    adopt_hits = sum(1 for r in adopted if r["choice"] == r["expect"])
    bad_confident = [
        r
        for r in scored
        if isinstance(r["pmax"], (int, float)) and r["pmax"] >= 0.8 and r["choice"] != r["expect"]
    ]
    print(
        f"  → top-1 {hits}/{len(scored)} = {hits / len(scored):.0%}"
        f" · 门控后 {adopt_hits}/{len(adopted)} 采纳且正确"
        f"（{len(scored) - len(adopted)} 条 pmax<{THRESHOLD} → 能力引导）"
        f" · 高置信错误 {len(bad_confident)}"
        f" · p50 {statistics.median(lats):.0f} ms"
        f" · 平均 pmax {statistics.fmean(pm) if pm else float('nan'):.3f}"
        f" · 错误 {sum(1 for r in rows if r['error'])}"
    )
    for r in bad_confident:
        print(f"     ⚠ 高置信错误：{r['case']} 期望 {r['expect']} → {r['choice']} @{r['pmax']:.3f}")


def main() -> int:
    global HOST
    parser = argparse.ArgumentParser(description="决策模型本地影子评测")
    parser.add_argument("--models", nargs="*", default=DEFAULT_MODELS, help="ollaya 模型标签")
    parser.add_argument("--host", default=HOST, help="ollaya 服务地址")
    parser.add_argument("--json", dest="json_out", help="落原始结果到 JSON 文件")
    parser.add_argument("--probs", action="store_true", help="打印每个选项的概率")
    parser.add_argument(
        "--variants",
        help="文案变体 JSON 文件：{变体名: {业务键: description}}，批量对比用",
    )
    args = parser.parse_args()

    HOST = args.host.rstrip("/")
    lengths = {b: len(_capability_text(m)) for b, m in _MANIFESTS.items()}
    print(f"目标服务 {HOST} · 模型 {', '.join(args.models)} · criteria 字符数 {lengths}")
    variants = None
    if args.variants:
        raw = json.loads(Path(args.variants).read_text(encoding="utf-8"))
        # 只收 {业务键: 文案} 的字典项；``_`` 开头的键是注释（变体文件里的说明文字）
        variants = {k: v for k, v in raw.items() if isinstance(v, dict) and not k.startswith("_")}
        print(f"变体 {len(variants)} 个：{', '.join(variants)}")
    results = run(args.models, args.probs, variants)
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(results, fh, ensure_ascii=False, indent=2)
        print(f"\n原始结果：{args.json_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
