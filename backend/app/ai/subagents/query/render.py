"""``query`` 工具结果的卡片投影（ADR-0033 决策 11 / ADR-0042 卡片协议 v2）。

``TOOL_RESULT`` 存**原始载荷**（模型上下文 + 落库回放），本模块把同一份结果投影成
**类型化卡片**：

- ``Card.kind`` → ``DATA.data.type``，机器可读的**判别键**；
- ``Card.payload`` → ``DATA.data.result``，该种类的**结构化载荷**。

前端按 ``kind`` 分派到对应的卡片渲染器（``frontend/lib/features/assistant/presentation/
widgets/assistant_cards.dart``）；渲染器认不出的 ``kind`` 由降级卡兜住，不静默消失。

**v1 → v2 为什么改**（ADR-0042）：v1 的载荷是「早已拼好的展示字符串」
（``{type, subject, stem}``，明细用 ``；`` 连成一行），有两个硬伤——
① 排版固化在服务端，前端拿不到「哪段是学科、哪段是次数」；
② ``result.type``（**标签**「错题 / 今日任务」）与信封里的 ``data.type``（**种类**
``query``）同名异义，前端解析时只能二选一地误读，于是「按类型渲染不同卡片」在这套
契约下根本无从实现。v2 把 ``kind`` 收进信封、载荷只留结构化字段，标签改名 ``title``。

刻意不做的事：
- 不在此处做角色裁剪（裁剪只发生在工具侧的 ``project_for_role``，见 ADR-0033 决策 9）：
  本模块拿到的 result 已是投影后的安全载荷，再存一道判断只会制造第二个真相源。
- 不把 ``status`` 翻成中文：状态枚举 → 文案的映射属呈现层，前端已有
  （``parent_question_bank_view.dart`` 的 ``_statusLabel``），服务端只发机器值。
- 不输出原始 JSON：卡片是给人看的摘要，模型上下文另有 ``TOOL_RESULT`` 承载。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

# 工具 → 卡片种类（机器可读判别键，前端按它分派渲染器）。
# 新增工具必须在此登记，否则落到 ``notice`` 降级卡（有内容、不丢帧）。
_KIND: dict[str, str] = {
    "list_children": "child_list",
    "list_parent_tasks": "task_list",
    "list_today_tasks": "task_list",
    "list_wrong_questions": "wrong_question_list",
    "list_due_reviews": "due_review_list",
    "get_progress": "progress",
    "get_mastery": "mastery_list",
}

# 工具 → 卡头标签（人可读）。
_TITLE: dict[str, str] = {
    "list_children": "娃娃",
    "list_parent_tasks": "任务",
    "list_today_tasks": "今日任务",
    "list_wrong_questions": "错题",
    "list_due_reviews": "待复习",
    "get_progress": "学习进度",
    "get_mastery": "掌握度",
}

# 明细为空时的说明（区分「查过了但没有」与「压根没查」）。
_EMPTY_TEXT: dict[str, str] = {
    "list_parent_tasks": "暂无任务。",
    "list_today_tasks": "今天没有任务。",
    "list_wrong_questions": "没有错题记录。",
    "list_due_reviews": "今天没有到期复习。",
}

# 单张卡最多带多少条明细；超出部分只报 ``total``，由前端渲染「共 N 条」
# （避免刷屏 + 落库 payload 膨胀）。total 恒为真实命中数，前端据此判断是否截断。
_MAX_ITEMS = 5
_ITEM_TEXT_LIMIT = 60  # 单条明细的字符上限
_ITEM_TITLE_LIMIT = 40  # 任务标题的字符上限


@dataclass(frozen=True)
class Card:
    """一张展示卡：``kind`` 是种类判别键，``payload`` 是该种类的结构化载荷。"""

    kind: str
    payload: dict[str, Any] = field(default_factory=dict)


def _clip(text: Any, limit: int = _ITEM_TEXT_LIMIT) -> str:
    s = " ".join(str(text or "").split())
    return s if len(s) <= limit else f"{s[: limit - 1]}…"


def _as_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _as_float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _title_of(name: str) -> str:
    return _TITLE.get(name, "查询")


def _subject_of(block: dict[str, Any]) -> str:
    """归属标签：娃娃名（年级），如「小明（2年级）」。"""
    who = str(block.get("name") or "")
    grade = block.get("grade")
    if who and grade:
        return f"{who}（{grade}年级）"
    return who


def _task_item(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "title": _clip(item.get("title") or "任务", _ITEM_TITLE_LIMIT),
        "status": str(item.get("status") or ""),
        "question_count": len(item.get("questions") or []),
    }


def _wrong_question_item(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "subject": str(item.get("subject") or ""),
        "stem": _clip(item.get("stem")),
        "qtype": str(item.get("qtype") or ""),
        "wrong_count": _as_int(item.get("wrong_count")),
    }


def _due_review_item(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "subject": str(item.get("subject") or ""),
        "stem": _clip(item.get("stem")),
        "qtype": str(item.get("qtype") or ""),
        "review_stage": _as_int(item.get("review_stage")),
    }


def _mastery_item(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "knowledge_point": str(item.get("knowledge_point") or "知识点"),
        "subject": str(item.get("subject") or ""),
        "score": _as_float(item.get("score")),
        "level": str(item.get("level") or ""),
        "active_wrong": _as_int(item.get("active_wrong")),
    }


# 明细投影表：工具 → 单条明细的结构化形状。缺登记即降级为「标题 + 文本」。
_ITEM_SHAPERS = {
    "list_parent_tasks": _task_item,
    "list_today_tasks": _task_item,
    "list_wrong_questions": _wrong_question_item,
    "list_due_reviews": _due_review_item,
    "get_mastery": _mastery_item,
}


def _progress_stats(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "total": _as_int(item.get("total")),
        "correct": _as_int(item.get("correct")),
        "accuracy": _as_float(item.get("accuracy")),
        "streak_days": _as_int(item.get("streak_days")),
        "checkin_days": _as_int(item.get("checkin_days")),
    }


def _items_of(name: str, raw: list[Any]) -> list[dict[str, Any]]:
    shape = _ITEM_SHAPERS.get(name)
    if shape is None:
        # 未登记明细形状的工具（如 list_children）：只当计数，不猜字段。
        return []
    return [shape(i) for i in raw if isinstance(i, dict)]


def _card(
    *,
    kind: str,
    title: str,
    subject: str = "",
    items: list[dict[str, Any]] | None = None,
    total: int = 0,
    text: str = "",
    stats: dict[str, Any] | None = None,
) -> Card:
    payload: dict[str, Any] = {"title": title, "subject": subject}
    if stats is not None:
        payload["stats"] = stats
    if items:
        payload["items"] = items
    if total:
        payload["total"] = total
    if text:
        payload["text"] = text
    return Card(kind=kind, payload=payload)


def _notice(title: str, text: str) -> Card:
    """无结构可言的卡片：查询失败。走 ``notice`` 种类（前端按提示卡渲染）。"""
    return Card(kind="notice", payload={"title": title, "text": text})


def _block_cards(name: str, block: dict[str, Any]) -> list[Card]:
    title = _title_of(name)
    kind = _KIND.get(name, "notice")
    subject = _subject_of(block)

    if name == "list_children":
        # 定位类工具：明细为空是正常的，卡片本身就是「这个娃娃可查」。
        return [_card(kind=kind, title=title, subject=subject, text="可查询的娃娃")]

    raw = [i for i in (block.get("items") or []) if i is not None]
    if not raw:
        return [
            _card(
                kind=kind,
                title=title,
                subject=subject,
                text=_EMPTY_TEXT.get(name, "暂无数据。"),
            )
        ]

    if name == "get_progress":
        # 进度是单条聚合：明细位放 stats，不放 items（前端据此选指标卡版式）。
        item = raw[0] if isinstance(raw[0], dict) else {}
        return [
            _card(kind=kind, title=title, subject=subject, stats=_progress_stats(item))
        ]

    shaped = _items_of(name, raw)
    if not shaped:
        return [_card(kind=kind, title=title, subject=subject, text="暂无数据。")]
    return [
        _card(
            kind=kind,
            title=title,
            subject=subject,
            items=shaped[:_MAX_ITEMS],
            total=len(shaped),
        )
    ]


def render_cards(name: str, result: Any) -> list[Card]:
    """工具结果 → 卡片列表（空列表表示不产帧；调用方按需补 DATA 帧）。"""
    title = _title_of(name)
    kind = _KIND.get(name, "notice")

    if not isinstance(result, dict):
        return []
    if "error" in result:
        # 工具层把「查不到 / 越权 / 入参不合法」归一为 error 文本回灌模型；
        # 同一条话也如实展示给人，避免模型转述时添油加醋。
        return [_notice(title, f"查询失败：{result['error']}")]

    cards: list[Card] = []
    for block in result.get("children") or []:
        if isinstance(block, dict):
            cards.extend(_block_cards(name, block))

    spare = [i for i in (result.get("unassigned_items") or []) if i is not None]
    if spare:
        shaped = _items_of(name, spare)
        cards.append(
            _card(
                kind=kind,
                title=f"{title}·未指派",
                subject="未指派",
                items=shaped[:_MAX_ITEMS],
                total=len(shaped),
                text="" if shaped else "暂无数据。",
            )
        )

    if not cards:
        cards.append(_card(kind=kind, title=title, text="没有查到相关数据。"))
    return cards


__all__ = ["Card", "render_cards"]
