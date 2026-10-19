"""缺槽追问的话术（ADR-0100）：把「还缺哪几项」念成**一句话**。

**为什么不在 ``slot_filling.py``**：那个模块是通用引擎——对任意业务的
``input_schema`` 都同样工作，只答「缺不缺」。而「怎么念给人听」是展示层决策，
写进引擎会让引擎因为「改一句文案」而被改动（Divergent Change，与
``slot_summary.py`` 同一条理由）。

## 为什么要改（ADR-0100）

旧实现把每个缺槽的 ``prompt`` 各占一行、各配一组取值 chip 铺在气泡下方。
用户要补三项就得点三次（每次只回传一个槽的值），而**一次说全**
（「三年级数学选择题」）本来就完全可行——预检按正则一次能抽满三个槽。
追问的目的只是「告诉用户还差什么」，不是「拆成表单让人填」。

故取舍：**只留文本引导，不再铺选项 chip**。话术必须回答两件事——

1. 还差什么（槽的中文标签，如「科目 / 年级 / 题型」）；
2. 怎么一次说清（给一个可照抄的示例句，用户原样回一句即可）。

``clarify.missing_slots`` 结构化载荷仍然下发：它是**协议**（历史回放、汇总卡、
读屏与后续能力都依赖它），本次只改渲染，不改协议。
"""
from __future__ import annotations

# 槽名 → 中文标签（与 ``slot_summary.SLOT_LABELS`` 同一套口径）。
_LABELS: dict[str, str] = {
    "subject": "科目",
    "grade": "年级",
    "qtype": "题型",
    "count": "数量",
    "difficulty": "难度",
    "knowledge_point": "知识点",
    "semester": "学期",
    "multi": "是否多选",
    "judge": "是否判断题",
    "multi_subject": "是否多学科组卷",
    "question_text": "问题",
}

# 示例句只给「怎么一次说完」，不逐槽列举选项——选项一列就退回表单了。
_EXAMPLE = "例如：三年级数学、选择题、5 道"


def _label(name: str) -> str:
    """槽名 → 中文标签；未知槽退回槽名本身（不抛，纯展示）。"""
    return _LABELS.get(name, name)


def clarify_sentence(missing: list[dict]) -> str:
    """把缺槽清单拼成一句引导（含示例，用户可一句补齐）。

    ``missing`` 是 ``fill_slots`` 产出的 ``missing_slots``（每项至少带 ``name``）。
    空列表返回空串——调用方据此判断「本轮不是澄清」。
    """
    names = [_label(m.get("name", "")) for m in missing if m.get("name")]
    if not names:
        return ""
    if len(names) == 1:
        head = f"还差{names[0]}，补一句就行。"
    else:
        head = f"还差{'、'.join(names)}这几项，可以一次说完。"
    return f"{head}{_EXAMPLE}"


def clarify_prompts(missing: list[dict]) -> str:
    """各缺槽 ``prompt`` 的原句拼接（保留给需要逐项措辞的消费方 / 日志）。

    ⚠️ 不再作为气泡正文：逐句拼接在气泡里会念成一串反问，且与
    ``clarify_sentence`` 的「一次说完」互相打脸。正文只用 ``clarify_sentence``。
    """
    return " ".join(m.get("prompt", "") for m in missing if m.get("prompt"))
