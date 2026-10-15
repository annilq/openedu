"""出题规格汇总（ADR-0095）：``question`` 业务专属的文案与前端结构化载荷。

**为什么不在 ``slot_filling.py``**：那个模块是通用引擎——对任意业务的
``input_schema`` 都同样工作，不含任何 question 专属知识。而汇总文案天生是
question 专属（科目/年级/题型…），写在引擎里会让引擎因为「另一个业务要改一句
文案」而被改动（Divergent Change）。故二者分开：引擎只答「缺不缺」，汇总只管
「怎么念给人听」。

汇总同时给出**结构化载荷**（``slots``），供前端渲染「已确认规格」卡与「修改」
入口——复用澄清帧同一套 name/type/enum/min/max 形状，前端无需第二套解析。
"""
from __future__ import annotations

from typing import Any

from app.features.assistant.slot_filling import resolve_enum_ref

# 槽名 → 中文标签（汇总文案与前端汇总卡共用）。
SLOT_LABELS: dict[str, str] = {
    "subject": "科目",
    "grade": "年级",
    "qtype": "题型",
    "count": "数量",
    "difficulty": "难度",
    "knowledge_point": "知识点",
    "semester": "学期",
    "multi": "多选",
    "judge": "判断题",
    "multi_subject": "多学科组卷",
}

# 英文码 → 中文（enum 槽的可读文案）。
QTYPE_LABELS: dict[str, str] = {
    "choice": "选择题",
    "fill": "填空题",
    "calc": "计算题",
    # 「应用题」而非「解答题」：与前端 shared/utils/question_labels.dart 的
    # qtypeLabelFull 同一套文案，避免同一题型两处念法不同。
    "open": "应用题",
}
DIFFICULTY_LABELS: dict[str, str] = {
    "easy": "简单",
    "medium": "中等",
    "hard": "困难",
}
SEMESTER_LABELS: dict[str, str] = {"上": "上学期", "下": "下学期"}

_UNSET = "（未指定）"

# 汇总里要念出来的槽（按此顺序）；bool/多选等辅助槽不占版面。
_SUMMARY_ORDER: tuple[str, ...] = (
    "subject",
    "grade",
    "qtype",
    "count",
    "difficulty",
    "knowledge_point",
)


def label_of(name: str) -> str:
    """槽名 → 中文标签；未知槽退回槽名本身（不抛，纯展示）。"""
    return SLOT_LABELS.get(name, name)


def value_label(name: str, value: Any) -> str:
    """槽值 → 中文可读文案；空值统一为「（未指定）」。

    英文码（题型/难度/学期）必须翻译——直接把 ``choice`` 念给用户既不可读，
    也与 US5「生成前有机会修正」的意图相悖（看不懂就没法改）。
    """
    if value is None or value == "":
        return _UNSET
    if isinstance(value, bool):
        return "是" if value else "否"
    text = str(value)
    if name == "qtype":
        return QTYPE_LABELS.get(text, text)
    if name == "difficulty":
        return DIFFICULTY_LABELS.get(text, text)
    if name == "semester":
        return SEMESTER_LABELS.get(text, text)
    return text


def summarize_slots(merged: dict) -> str:
    """「已确认规格」一行文案（后端兼容纯文本消费方 / 日志）。"""
    parts = [
        f"{label_of(name)}={value_label(name, merged.get(name))}"
        for name in _SUMMARY_ORDER
    ]
    return "已确认规格：" + " ".join(parts)


def summary_payload(schema: list[dict], merged: dict) -> list[dict]:
    """前端汇总卡载荷：每项 = 槽名/标签/当前值/可读值 + 可改形状（type/enum/min/max）。

    形状与澄清帧的 ``missing_slots`` 对齐，前端复用同一套 chip / 输入控件渲染
    「修改」入口，不再引入第二套协议。
    """
    out: list[dict] = []
    for slot in schema:
        name = slot["name"]
        if name not in merged:
            continue
        out.append(
            {
                "name": name,
                "label": label_of(name),
                "prompt": slot.get("prompt", ""),
                "type": slot["type"],
                # enum_ref 必须解析成具体选项：学科走 app.domain.subjects.SUBJECTS，
                # 不解析前端就渲染不出「语文 / 英语」修改项。
                "enum": slot.get("enum") or resolve_enum_ref(slot.get("enum_ref")),
                "min": slot.get("min"),
                "max": slot.get("max"),
                "value": merged.get(name),
                "value_label": value_label(name, merged.get(name)),
            }
        )
    return out
