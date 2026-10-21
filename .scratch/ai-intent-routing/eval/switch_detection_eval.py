"""会话内「意图切换检测」实测（ticket 14 / L1 的输入）。

问题：续轮如果沿用 ``Conversation.kind`` 而不再跑全量路由，用户中途改主意怎么办？
需要一个**便宜且敏感**的「是否换业务」检测器。本脚本用真实 provider 量两件事：

1. 延迟：全量 ``classify_llm``（三选一 + reason + confidence）vs 极简二分类
   （只输出 ``switch: bool``）。二者差多少，决定了「沿用 + 检测」是否真的省钱。
2. 准确率：检测器把「真切换」判成「不切换」（漏检）＝沿用错业务＝答非所问，是
   **有害错**；把「不切换」判成「切换」（误报）＝多付一次全量路由，只是延迟。
   两种错误代价不对称，故只接受「零漏检 + 低误报」。

用法::

    cd <repo>/backend
    .venv/bin/python ../.scratch/ai-intent-routing/eval/switch_detection_eval.py

只依赖标准库 + 本项目 + 真实 provider；拿不到 provider 就跳过（ticket 13 纪律）。
"""

from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import sys
import time
from pathlib import Path
from typing import Any

BACKEND = Path(__file__).resolve().parents[2] / "backend"
sys.path.insert(0, str(BACKEND))

from decision_model_eval import build_real_provider  # noqa: E402

from agent_core.adapters.llm_route import classify_llm  # noqa: E402
from agent_core.registry import discover_subagent_manifests  # noqa: E402
from agent_core.runtime import AgentRuntime  # noqa: E402

_MANIFESTS = discover_subagent_manifests()
_RUNTIME = AgentRuntime(_MANIFESTS)

# ── 用例：会话当前业务 + 近期历史 + 最新消息 + 是否真的切换 ──
# ``switch=True`` 的判据：最新消息的主责业务 ≠ 当前业务。
CASES: list[dict] = [
    {
        "case": "tutor 会话 · 追问同一题",
        "biz": "tutor",
        "history": [
            ("user", "23+45 怎么算"),
            ("assistant", "先算个位 3+5=8，再算十位 2+4=6，合起来 68。"),
        ],
        "message": "我还是不懂，再说一遍",
        "switch": False,
    },
    {
        "case": "tutor 会话 · 换一道同类型题",
        "biz": "tutor",
        "history": [
            ("user", "鸡兔同笼怎么解"),
            ("assistant", "设兔为 x，鸡为 y，列两个方程……"),
        ],
        "message": "那如果是 40 个头 110 只脚呢",
        "switch": False,
    },
    {
        "case": "tutor 会话 · 改要出题",
        "biz": "tutor",
        "history": [
            ("user", "帮我讲一下一元一次方程"),
            ("assistant", "一元一次方程的标准形式是 ax+b=0……"),
        ],
        "message": "好，那帮我出 5 道二元一次方程的选择题",
        "switch": True,
    },
    {
        "case": "tutor 会话 · 改要查数据",
        "biz": "tutor",
        "history": [
            ("user", "这道题选什么"),
            ("assistant", "选 B。因为……"),
        ],
        "message": "查一下我们班张三这单元的掌握度",
        "switch": True,
    },
    {
        "case": "tutor 会话 · 问助手能做什么",
        "biz": "tutor",
        "history": [
            ("user", "23+45 怎么算"),
            ("assistant", "68。"),
        ],
        "message": "对了，你都能帮我做什么？",
        "switch": True,
    },
    {
        "case": "tasks 会话 · 继续出题",
        "biz": "tasks",
        "history": [
            ("user", "出 5 道二元一次方程的选择题"),
            ("assistant", "已生成 5 道题。"),
        ],
        "message": "再来 3 道难度高一点的",
        "switch": False,
    },
    {
        "case": "tasks 会话 · 删除刚才的题",
        "biz": "tasks",
        "history": [
            ("user", "出 5 道二元一次方程的选择题"),
            ("assistant", "已生成 5 道题。"),
        ],
        "message": "第 2 题不合适，删掉",
        "switch": False,
    },
    {
        "case": "tasks 会话 · 改问解题",
        "biz": "tasks",
        "history": [
            ("user", "出 5 道二元一次方程的选择题"),
            ("assistant", "已生成 5 道题。"),
        ],
        "message": "第 3 题为什么答案是 C？怎么算的",
        "switch": True,
    },
    {
        "case": "tasks 会话 · 改要讲解概念",
        "biz": "tasks",
        "history": [
            ("user", "出 5 道二元一次方程的选择题"),
            ("assistant", "已生成 5 道题。"),
        ],
        "message": "算了不出了，你先给我讲讲什么是代入消元法",
        "switch": True,
    },
    {
        "case": "tasks 会话 · 继续查数据",
        "biz": "tasks",
        "history": [
            ("user", "今天有哪些学生的任务到期"),
            ("assistant", "共 3 人：张三、李四、王五。"),
        ],
        "message": "那他们各自的掌握度呢",
        "switch": False,
    },
    {
        "case": "capability 会话 · 改要出题",
        "biz": "capability",
        "history": [
            ("user", "你能做什么"),
            ("assistant", "我可以出题、查数据、辅导讲解……"),
        ],
        "message": "出一道鸡兔同笼的题",
        "switch": True,
    },
    {
        "case": "capability 会话 · 继续问能力",
        "biz": "capability",
        "history": [
            ("user", "你能做什么"),
            ("assistant", "我可以出题、查数据、辅导讲解……"),
        ],
        "message": "查数据具体能查哪些？",
        "switch": False,
    },
]

SWITCH_SYSTEM = (
    "你是教育助手的守门员。当前会话正由某个助手处理。"
    "判断用户的最新消息是否已经换成「另一个助手该处理的事」。"
    "只回答 switch：true 表示换了助手，false 表示仍由当前助手处理。"
    "拿不准时选 true——误报只是多判断一次，漏报会答非所问。"
)


def _switch_prompt(biz: str, state: str, message: str) -> str:
    text = _MANIFESTS[biz].routing_criteria or _MANIFESTS[biz].description
    return (
        f"当前助手：{biz}（{text}）\n\n"
        f"最近对话：\n{state}\n\n"
        f"用户最新消息：{message}\n\n"
        "这条消息是否换成别的助手处理了？"
    )


async def _measure_switch(
    provider: Any, biz: str, history: list[dict], message: str, *, with_state: bool
) -> tuple[bool | None, int]:
    """极简二分类：只输出 ``switch: bool``。返回 (判定, 毫秒)。"""
    from pydantic import BaseModel

    class SwitchVerdict(BaseModel):
        switch: bool

    state = (
        "\n".join(f"{t['role']}: {t['content']}" for t in (history or []))
        if with_state
        else "（无）"
    )
    prompt = _switch_prompt(biz, state, message)
    started = time.perf_counter()
    try:
        async for ev in provider.stream(SWITCH_SYSTEM, prompt, schema=SwitchVerdict):
            if type(ev).__name__ == "StructuredDone":
                data = ev.data
                val = data.get("switch") if isinstance(data, dict) else getattr(data, "switch", None)
                return bool(val), int((time.perf_counter() - started) * 1000)
    except Exception:  # noqa: BLE001 — 评测脚本：失败如实记为 None
        return None, int((time.perf_counter() - started) * 1000)
    return None, int((time.perf_counter() - started) * 1000)


async def _measure_full(provider: Any, history: list[dict], message: str, role: str):
    """全量分类（生产现状）：三选一 + reason + confidence。"""
    visible = _RUNTIME.visible_businesses(role)
    started = time.perf_counter()
    dec = await classify_llm(provider, history, message, _MANIFESTS, visible)
    return dec, int((time.perf_counter() - started) * 1000)


def _pct(vals: list[int]) -> str:
    if not vals:
        return "n/a"
    s = sorted(vals)
    return f"p50 {statistics.median(s):.0f} · p90 {s[int(len(s) * 0.9) - 1 if len(s) > 1 else 0]:.0f} · max {max(s)}"


async def run(role: str = "teacher") -> list[dict]:
    rows: list[dict] = []
    for c in CASES:
        history = [{"role": r, "content": t} for r, t in c["history"]]
        dec, full_ms = await _measure_full(_PROVIDER, history, c["message"], role)
        sw, sw_ms = await _measure_switch(
            _PROVIDER, c["biz"], history, c["message"], with_state=True
        )
        sw_ns, sw_ns_ms = await _measure_switch(
            _PROVIDER, c["biz"], history, c["message"], with_state=False
        )
        rows.append(
            {
                "case": c["case"],
                "biz": c["biz"],
                "expect_switch": c["switch"],
                "full_choice": dec.business if dec else None,
                "full_ms": full_ms,
                "switch": sw,
                "switch_ms": sw_ms,
                "switch_nostate": sw_ns,
                "switch_nostate_ms": sw_ns_ms,
            }
        )
    return rows


_PROVIDER: Any = None


def main() -> int:
    parser = argparse.ArgumentParser(description="会话内意图切换检测实测")
    parser.add_argument("--role", default="teacher", help="角色（决定可见业务集）")
    parser.add_argument("--json", dest="json_out", help="落原始结果到 JSON")
    args = parser.parse_args()

    built = build_real_provider()
    if built is None:
        print("无可用真实 provider，跳过（不得据此下结论）")
        return 1
    global _PROVIDER
    _PROVIDER, model_name = built
    print(f"provider: {model_name} · 角色 {args.role} · 用例 {len(CASES)} 条")

    rows = asyncio.run(run(args.role))

    print("\n=== 逐条 ===")
    for r in rows:
        verdict = "漏检(有害)" if (r["switch"] is False and r["expect_switch"]) else ""
        if r["switch"] is True and not r["expect_switch"]:
            verdict = "误报(多判一次)"
        print(
            f"  {r['case']:<26} 当前={r['biz']:<11} 期望切换={str(r['expect_switch']):<5} "
            f"检测={str(r['switch']):<5} {verdict:<12} "
            f"全量={r['full_ms']:>5}ms 检测={r['switch_ms']:>5}ms"
        )

    print("\n=== 延迟 ===")
    print(f"  全量分类（现状每轮都付）        {_pct([r['full_ms'] for r in rows])}")
    print(f"  极简二分类（带 2 轮历史）       {_pct([r['switch_ms'] for r in rows])}")
    print(f"  极简二分类（不带历史）          {_pct([r['switch_nostate_ms'] for r in rows])}")

    print("\n=== 检测器质量（漏检 = 沿用错业务 = 有害错）===")
    miss = [r for r in rows if r["switch"] is False and r["expect_switch"]]
    fp = [r for r in rows if r["switch"] is True and not r["expect_switch"]]
    none = [r for r in rows if r["switch"] is None]
    print(f"  漏检 {len(miss)} / {len(rows)}  误报 {len(fp)} / {len(rows)}  无产出 {len(none)}")
    if miss:
        print("  漏检明细：")
        for r in miss:
            print(f"    - {r['case']}（全量分类给了 {r['full_choice']}）")
    if fp:
        print("  误报明细：")
        for r in fp:
            print(f"    - {r['case']}（全量分类给了 {r['full_choice']}）")

    if args.json_out:
        Path(args.json_out).write_text(
            json.dumps({"model": model_name, "rows": rows}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"\n已写入 {args.json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
