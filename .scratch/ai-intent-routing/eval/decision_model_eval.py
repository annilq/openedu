"""决策模型本地影子评测（记忆 §10：差异要用实测说话，抽象 trait 不算数）。

用本项目**真实的路由请求形状**去问 ollaya 上的候选决策模型：

- ``state``  = ``agent_core.router._build_routing_state`` 的产物（近 N 轮 + 当前消息追尾）
- 选项      = ``_capability_text(manifest)`` 投影出的能力清单（键 = 业务键）
- 问题      = ``LayaDecisionModel.decide`` 里那句「应由哪个助手继续处理用户的最新消息？」

评测三件事：中文 top-1 准确率、**校准后的置信度**（供 ``threshold=0.5`` 门控参考）、
以及长历史是否触发 ``422 STATE_TRUNCATED``（验证 512 / 1024 上下文的实际边界）。

用法（ollaya 需在 127.0.0.1:11435 运行）：:

    ollaya pull laya:multilingual && ollaya pull largha
    python decision_model_eval.py                       # 默认两个模型
    python decision_model_eval.py --models largha        # 只跑一个
    python decision_model_eval.py --json out.json        # 落原始数据

只依赖标准库；显式绕过系统代理（macOS 代理会把 localhost 请求也吞掉）。
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
import urllib.error
import urllib.request

HOST = "http://127.0.0.1:11435"
DEFAULT_MODELS = ["laya:multilingual", "largha"]

# 与 agent_core/adapters/laya.py 保持同源
INSTRUCTIONS = "给定以上对话，应由哪个助手继续处理用户的最新消息？"

# 与 app/ai/subagents/*/manifest.py 的 name / description / actions 保持同源
CAPABILITY = {
    "tasks": (
        "任务学情与出题助手\n"
        "查询任务 / 错题 / 进度 / 掌握度 / 待复习与学生名单（学生查自己）；"
        "按科目、年级、题型与数量生成题目题卡（含选项与解析）；"
        "教师还可管理题库（查询 / 归档 / 删除）并从题库组建草稿任务（确认后发布）。\n"
        "actions: task_generate"
    ),
    "capability": (
        "能力自述\n"
        "说明助手能做什么、不能做什么，并给出可点方向；不调用模型，返回服务端固定清单。"
    ),
    "tutor": "伴学答疑\n针对学生的提问给出适龄、纯学习相关的讲解。",
}

# 可见集（ADR-0098 二执行体 + ADR-0079 能力自述）
TEACHER = ["tasks", "capability", "tutor"]
STUDENT = ["capability", "tutor"]

# (用例 id, 角色, 期望业务或 None=不计分, 当前消息, 历史轮次)
CASES: list[tuple[str, str, str | None, str, list[tuple[str, str]] | None]] = [
    # ── 首轮：动作明确 ──
    ("T01 首轮出题", "teacher", "tasks", "帮我出 2 道四年级数学题", None),
    ("T02 出一道（旧坑）", "teacher", "tasks", "出一道四年级数学题", None),
    ("T03 来一道", "teacher", "tasks", "来一道三年级分数的题", None),
    ("T04 查学情", "teacher", "tasks", "我班有哪些学生", None),
    ("T05 查错题", "teacher", "tasks", "我的错题有哪些", None),
    ("T06 元问题", "teacher", "capability", "你能做什么", None),
    ("T07 纯讲解", "teacher", "tutor", "这道题为什么选 B", None),
    # ── 续接：历史决定去留（trace 73000ee0 的失败形状）──
    (
        "T08 续接改年级",
        "teacher",
        "tasks",
        "数学",
        [
            ("user", "帮我出 2 道四年级数学题"),
            ("assistant", "好的，这是两道四年级数学题…"),
        ],
    ),
    (
        "T09 续接换学科",
        "teacher",
        "tasks",
        "换成四年级的分数题",
        [
            ("user", "帮我出 2 道五年级数学题"),
            ("assistant", "好的，这是两道五年级数学题…"),
        ],
    ),
    (
        "T10 续接转讲解",
        "teacher",
        "tutor",
        "第一题怎么算的？",
        [
            ("user", "帮我出 2 道四年级数学题"),
            ("assistant", "好的：① 24×15=？ ② 3.6+2.75=？"),
        ],
    ),
    # ── 学生端（只暴露 capability / tutor）──
    ("S01 提问求解", "student", "tutor", "23 + 45 怎么算", None),
    ("S02 元问题", "student", "capability", "你能帮我做什么", None),
    ("S03 续接", "student", "tutor", "还是不懂", [("user", "什么是分数"), ("assistant", "分数表示整体的一部分…")]),
    # ── 模糊句：预期不稳，不计分，只观察置信度是否诚实（低置信=可安全回落引导）──
    ("X01 闲聊", "teacher", None, "随便聊聊", None),
    ("X02 空泛", "teacher", None, "你好呀", None),
]


def build_state(current: str, history: list[tuple[str, str]] | None) -> str:
    """复刻 ``router._build_routing_state``：历史在前，当前消息追尾。"""
    parts = [f"{role}: {content}" for role, content in (history or [])]
    parts.append(f"user: {current}")
    return "\n".join(parts)


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


def ask(model: str, state: str, businesses: list[str]) -> dict:
    """POST /v1/systemone（TypeSafe 兼容形状），返回评测记录行。"""
    payload = {
        "model": model,
        "state": state,
        "questions": {
            "business": {
                "type": "choice",
                "instructions": INSTRUCTIONS,
                "criteria": {b: CAPABILITY[b] for b in businesses},
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
            "confidence": None,
        }
    except Exception as exc:  # noqa: BLE001 — 评测脚本，任何失败都记录为错误
        return {
            "latency_ms": int((time.monotonic() - started) * 1000),
            "error": f"{type(exc).__name__}: {exc}",
            "choice": None,
            "confidence": None,
        }
    latency = int((time.monotonic() - started) * 1000)
    answer = (raw.get("answers") or {}).get("business") or {}
    return {
        "latency_ms": latency,
        "error": None,
        "choice": answer.get("choice"),
        "confidence": answer.get("confidence"),
        "probabilities": answer.get("probabilities") or {},
        "served_model": raw.get("model"),
    }


def run(models: list[str], show_probs: bool = False) -> dict:
    results: dict[str, list[dict]] = {}
    for model in models:
        # 预热：首次请求要加载模型，不进统计
        warm = ask(model, "user: 你好", TEACHER)
        rows: list[dict] = []
        for case_id, role, expect, current, history in CASES:
            businesses = TEACHER if role == "teacher" else STUDENT
            state = build_state(current, history)
            got = ask(model, state, businesses)
            got.update(
                case=case_id,
                role=role,
                expect=expect,
                state_chars=len(state),
                scored=expect is not None,
            )
            rows.append(got)
            if show_probs:
                print(f"    {got.get('probabilities')}")
        # 上下文边界：长历史单独打点（不计入主表准确率）
        long_row = ask(model, long_state(), TEACHER)
        long_row.update(case="L00 长历史(12轮)", role="teacher", expect="tasks", state_chars=len(long_state()))
        results[model] = rows
        results[f"{model}#long"] = [long_row]
        _print_model(model, rows, long_row, warm)
    return results


def _print_model(model: str, rows: list[dict], long_row: dict, warm: dict) -> None:
    print(f"\n══ {model}（预热 {warm['latency_ms']} ms）══")
    print(f"{'用例':<20}{'期望':<12}{'实得':<12}{'判':<4}{'置信':<8}{'ms':>6}  备注")
    scored = [r for r in rows if r["scored"]]
    for r in rows:
        mark = "" if not r["scored"] else ("✓" if r["choice"] == r["expect"] else "✗")
        conf = r["confidence"]
        conf_s = f"{conf:.3f}" if isinstance(conf, (int, float)) else "—"
        note = (r["error"] or "")[:60]
        if not r["scored"]:
            note = "不计分（模糊句）· " + note
        print(
            f"{r['case']:<20}{r['expect'] or '—':<12}{r['choice'] or '—':<12}{mark:<4}"
            f"{conf_s:<8}{r['latency_ms']:>6}  {note}"
        )
    long_note = long_row["error"] or f"{long_row['choice']} @{long_row['confidence']}"
    print(f"{'长历史 12 轮':<20}{'tasks':<12}{long_row['choice'] or '—':<12}{'—':<4}"
          f"{'—':<8}{long_row['latency_ms']:>6}  {long_note[:60]}")
    hits = sum(1 for r in scored if r["choice"] == r["expect"])
    lats = [r["latency_ms"] for r in rows]
    confs = [r["confidence"] for r in scored if isinstance(r["confidence"], (int, float))]
    print(
        f"  → 准确率 {hits}/{len(scored)} = {hits / len(scored):.0%}"
        f" · p50 {statistics.median(lats):.0f} ms"
        f" · 平均置信 {statistics.fmean(confs) if confs else float('nan'):.3f}"
        f" · 错误 {sum(1 for r in rows if r['error'])}"
    )


def main() -> int:
    global HOST
    parser = argparse.ArgumentParser(description="决策模型本地影子评测")
    parser.add_argument("--models", nargs="*", default=DEFAULT_MODELS, help="ollaya 模型标签")
    parser.add_argument("--host", default=HOST, help="ollaya 服务地址")
    parser.add_argument("--json", dest="json_out", help="落原始结果到 JSON 文件")
    parser.add_argument("--probs", action="store_true", help="打印每个选项的概率")
    args = parser.parse_args()

    HOST = args.host.rstrip("/")
    print(f"目标服务 {HOST} · 模型 {', '.join(args.models)}")
    results = run(args.models, args.probs)
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(results, fh, ensure_ascii=False, indent=2)
        print(f"\n原始结果：{args.json_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
