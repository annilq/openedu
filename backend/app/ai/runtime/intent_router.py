"""意图路由（ADR-0024：混合路由）。

规则优先：逐个匹配可见 subagent 清单里的 ``triggers``（关键词/示例短语），
命中即路由；未命中走轻量 LLM 分类（需真实引擎，否则跳过）；两者皆空则启发式兜底。

启发式保证在无 key（mock）环境下也能给出合理默认：出题/查任务优先命中对应
subagent，其余一律伴学答疑（tutor）。LLM 兜底为有真实引擎时的增强项，缺失即降级，
不阻断主流程。
"""
from __future__ import annotations

from typing import Awaitable, Callable, Sequence

from app.ai.runtime.manifest import SubAgentManifest

# 启发式兜底词表（与 manifest.triggers 解耦，作为最后一层保障）
_QUESTION_HINTS = ("出题", "出几道", "出道", "出道题目", "出题目", "题目", "测验", "考考", "练", "生成题", "来几道", "给我题")
_TASK_HINTS = ("任务", "作业", "练习册", "查看", "列出", "查询", "有哪些", "什么题", "任务里的题", "任务题目")
# subagent 派发优先级（命中多业务时更具体的先赢）。
# tasks 优先于 question：避免「任务题目」被 question 的泛触发词「题目」抢匹配。
_PRIORITY = ("tasks", "question", "tutor")


def _norm(text: str) -> str:
    return (text or "").strip().lower()


def _rule_match(text: str, businesses: Sequence[str], manifests: dict[str, SubAgentManifest]) -> str | None:
    low = _norm(text)
    for biz in _PRIORITY:
        if biz not in businesses:
            continue
        for trig in manifests[biz].triggers:
            if _norm(trig) in low:
                return biz
    # 非优先级业务也尝试规则匹配
    for biz in businesses:
        if biz in _PRIORITY:
            continue
        for trig in manifests[biz].triggers:
            if _norm(trig) in low:
                return biz
    return None


def _heuristic(text: str, businesses: Sequence[str]) -> str:
    low = _norm(text)
    if "tasks" in businesses and any(h in low for h in _TASK_HINTS):
        return "tasks"
    if "question" in businesses and any(h in low for h in _QUESTION_HINTS):
        return "question"
    # 默认伴学答疑（tutor 始终存在）
    return "tutor" if "tutor" in businesses else (businesses[0] if businesses else "tutor")


async def classify(
    text: str,
    *,
    available: Sequence[str],
    manifests: dict[str, SubAgentManifest],
    llm_classify: Callable[[str, Sequence[str]], Awaitable[str | None]] | None = None,
) -> str:
    """把自由文本路由到某个可见 business。

    链路：规则匹配 →（可选）LLM 分类 → 启发式兜底。
    """
    if not available:
        return "tutor"

    ruled = _rule_match(text, available, manifests)
    if ruled is not None:
        return ruled

    if llm_classify is not None:
        try:
            llm = await llm_classify(text, available)
            if llm in available:
                return llm
        except Exception:  # noqa: BLE001 — LLM 兜底失败不影响主流程
            pass

    return _heuristic(text, available)
