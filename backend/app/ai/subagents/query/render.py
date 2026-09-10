"""``query`` 工具结果的卡片投影（ADR-0033 决策 11：呈现契约双轨）。

``TOOL_RESULT`` 存**原始载荷**（模型上下文 + 落库回放），本模块把同一份结果转成
前端既有卡片形状 ``{type, subject, stem}``（``floating_assistant.dart`` 的 ``_CardTile``
消费契约：读 ``type`` / ``subject`` / ``stem``，``stem`` 为空则不渲染），再由
``QuerySubAgent.render_tool_result`` 补发为 ``DATA`` 帧——**前端零改动**。

刻意不做的事：
- 不在此处做角色裁剪（裁剪只发生在工具侧的 ``project_for_role``，见 ADR-0033 决策 9）：
  本模块拿到的 result 已是投影后的安全载荷，再存一道判断只会制造第二个真相源。
- 不输出原始 JSON：卡片是给人看的摘要，模型上下文另有 ``TOOL_RESULT`` 承载。
"""
from __future__ import annotations

from typing import Any

# 最多把多少条明细折进一张卡片；超出部分只说总数（避免刷屏 + 落库 payload 膨胀）。
_MAX_LINES = 5
_LINE_LIMIT = 40  # 单条明细的字符上限

# 工具 → 卡片类型标签（前端展示 `subject · type`）
_LABELS: dict[str, str] = {
    "list_children": "娃娃",
    "list_parent_tasks": "任务",
    "list_today_tasks": "今日任务",
    "list_wrong_questions": "错题",
    "list_due_reviews": "待复习",
    "get_progress": "学习进度",
    "get_mastery": "掌握度",
}

# 明细为空时的说明（区分「查过了但没有」与「压根没查」）
_EMPTY_TEXT: dict[str, str] = {
    "list_parent_tasks": "暂无任务。",
    "list_today_tasks": "今天没有任务。",
    "list_wrong_questions": "没有错题记录。",
    "list_due_reviews": "今天没有到期复习。",
}

_STATUS_CN = {"draft": "草稿", "assigned": "已派发", "done": "已完成"}


def _clip(text: Any) -> str:
    s = " ".join(str(text or "").split())
    return s if len(s) <= _LINE_LIMIT else f"{s[: _LINE_LIMIT - 1]}…"


def _line(name: str, item: Any) -> str:
    """把一条明细折成一行摘要；字段缺失时降级为空串（不抛错、不炸整条流）。"""
    if not isinstance(item, dict):
        return _clip(item)

    if name in {"list_parent_tasks", "list_today_tasks"}:
        title = item.get("title") or "任务"
        status = _STATUS_CN.get(str(item.get("status") or ""), str(item.get("status") or ""))
        count = len(item.get("questions") or [])
        tail = "、".join(x for x in (status, f"{count} 题" if count else "") if x)
        return f"{title}（{tail}）" if tail else str(title)

    if name == "list_wrong_questions":
        subject = item.get("subject") or ""
        prefix = f"[{subject}] " if subject else ""
        return f"{prefix}{_clip(item.get('stem'))}（错 {item.get('wrong_count', 0)} 次）"

    if name == "list_due_reviews":
        subject = item.get("subject") or ""
        prefix = f"[{subject}] " if subject else ""
        return f"{prefix}{_clip(item.get('stem'))}（第 {item.get('review_stage', 0)} 阶段）"

    if name == "get_progress":
        total = item.get("total", 0)
        correct = item.get("correct", 0)
        accuracy = item.get("accuracy", 0) or 0
        return (
            f"答对 {correct}/{total}（正确率 {accuracy:.0%}），"
            f"连续打卡 {item.get('streak_days', 0)} 天"
        )

    if name == "get_mastery":
        kp = item.get("knowledge_point") or "知识点"
        return f"{kp}：{item.get('score', 0)} 分（{item.get('level', '')}）"

    return _clip(item)


def _subject_of(block: dict[str, Any]) -> str:
    name = str(block.get("name") or "")
    grade = block.get("grade")
    if name and grade:
        return f"{name}（{grade}年级）"
    return name


def _block_cards(name: str, block: dict[str, Any], label: str) -> list[dict[str, str]]:
    if name == "list_children":
        # 定位类工具：明细为空是正常的，卡片本身就是「这个娃娃可查」。
        return [{"type": label, "subject": _subject_of(block), "stem": "可查询的娃娃"}]

    items = [i for i in (block.get("items") or []) if i is not None]
    if not items:
        return [
            {
                "type": label,
                "subject": _subject_of(block),
                "stem": _EMPTY_TEXT.get(name, "暂无数据。"),
            }
        ]

    lines = [_line(name, i) for i in items[:_MAX_LINES]]
    if len(items) > _MAX_LINES:
        lines.append(f"…共 {len(items)} 条")
    return [{"type": label, "subject": _subject_of(block), "stem": "；".join(t for t in lines if t)}]


def render_cards(name: str, result: Any) -> list[dict[str, str]]:
    """工具结果 → 卡片列表（空列表表示不产帧；调用方按需补 DATA 帧）。"""
    label = _LABELS.get(name, "查询")

    if not isinstance(result, dict):
        return []
    if "error" in result:
        # 工具层把「查不到 / 越权 / 入参不合法」归一为 error 文本回灌模型；
        # 同一条话也如实展示给人，避免模型转述时添油加醋。
        return [{"type": label, "subject": "", "stem": f"查询失败：{result['error']}"}]

    cards: list[dict[str, str]] = []
    for block in result.get("children") or []:
        if isinstance(block, dict):
            cards.extend(_block_cards(name, block, label))

    spare = [i for i in (result.get("unassigned_items") or []) if i is not None]
    if spare:
        lines = [_line(name, i) for i in spare[:_MAX_LINES]]
        if len(spare) > _MAX_LINES:
            lines.append(f"…共 {len(spare)} 条")
        cards.append(
            {
                "type": f"{label}·未指派",
                "subject": "未指派",
                "stem": "；".join(t for t in lines if t),
            }
        )

    if not cards:
        cards.append({"type": label, "subject": "", "stem": "没有查到相关数据。"})
    return cards


__all__ = ["render_cards"]
