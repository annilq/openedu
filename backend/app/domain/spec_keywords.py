"""出题规格的关键词 / 正则表（ADR-0095 §2.2）：**单一真源**。

两处消费者共用本模块，绝不再各抄一份：

- ``app.ai.subagents.question.agent.parse_specs_from_text``：自由文本一句话出题。
- ``app.features.assistant.slot_filling``：缺槽预检的确定性抽取。

历史教训：两份逐字复制的表（``_QTYPE_MAP`` / ``_SUBJECT_ALIASES`` / ``_CN_NUM``）
曾并存，改一处忘另一处即产生「同一句话两个解析结果」。本模块只放**表与正则**，
不放决策逻辑——两侧的取值范围与容错策略本就不同（出题侧学科面宽，预检侧必须
收敛到 ``SUBJECTS``），决策差异留在各自调用点。
"""
from __future__ import annotations

import re

# 学科别名 → 标准学科名（自由文本容错）。
SUBJECT_ALIASES: dict[str, str] = {
    "数学": "数学",
    "语文": "语文",
    "英语": "英语",
    "英文": "英语",
    "科学": "科学",
    "物理": "物理",
    "化学": "化学",
    "生物": "生物",
    "历史": "历史",
    "地理": "地理",
    "政治": "政治",
    "道法": "政治",
    "美术": "美术",
    "音乐": "音乐",
    "体育": "体育",
    "信息": "信息",
}

# 题型中文关键词 → 标准英文码（ADR-0004 D5：qtype ∈ choice/fill/calc/open；
# 判断题 = choice + 对/错选项）。遍历顺序即优先级，先命中先返回。
QTYPE_KEYWORDS: dict[str, str] = {
    "选择": "choice",
    "单选": "choice",
    "选择题": "choice",
    "多选": "choice",
    "填空": "fill",
    "填空题": "fill",
    "判断": "choice",
    "判断题": "choice",
    "计算": "calc",
    "计算题": "calc",
    "应用题": "calc",
    "问答": "open",
    "解答": "open",
    "简答题": "open",
    "问答题": "open",
    "解答题": "open",
}

# 难度中文关键词 → 标准英文码。
DIFFICULTY_KEYWORDS: dict[str, str] = {
    "简单": "easy",
    "容易": "easy",
    "中等": "medium",
    "适中": "medium",
    "难": "hard",
    "困难": "hard",
    "难题": "hard",
}

# bool 槽的关键词（出现即视为 True）。键 = 槽名。
BOOL_SLOT_KEYWORDS: dict[str, tuple[str, ...]] = {
    "multi": ("多选", "多选题"),
    "judge": ("判断题", "判断对错", "判断正误"),
    "multi_subject": ("多学科", "组卷", "多学科组卷"),
}

# 中文数字 → 阿拉伯数字（年级 / 数量抽取共用）。
CN_NUM: dict[str, int] = {
    "一": 1,
    "二": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
}

# 年级：「3年级」「三年级」——只认「N年级」，绝不能用于 count（会串味）。
GRADE_RE = re.compile(r"(\d)\s*年级")
GRADE_CN_RE = re.compile(r"([一二三四五六七八九])\s*年级")
# 数量：「2道」「2题」「2个」——只认量词，绝不能用于 grade。
COUNT_RE = re.compile(r"(\d+)\s*(道|题|个)")
COUNT_CN_RE = re.compile(r"([一二三四五])\s*(道|题)")


def cn_to_int(raw: str) -> int | None:
    """正则捕获组 → int（阿拉伯数字或中文数字）；无法解析返回 ``None``。"""
    if raw.isdigit():
        return int(raw)
    return CN_NUM.get(raw)
