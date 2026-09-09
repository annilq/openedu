"""伴学 SubAgent 清单（ADR-0024）。

双端通用（roles: parent + child，ADR-0026）：娃娃端只暴露伴学答疑，不暴露出题/答案。
triggers 覆盖「为什么/怎么/讲解/不会」等问答意图。
"""
from __future__ import annotations

MANIFEST = {
    "business": "tutor",
    "name": "伴学答疑",
    "description": "针对孩子的提问给出适龄、纯学习相关的讲解。",
    "roles": ["parent", "child"],
    "triggers": [
        "为什么", "怎么", "怎样", "讲解", "不会", "不懂", "是什么意思",
        "教我", "帮我讲", "解答", "原理", "如何", "为什么是",
    ],
    "tools": ["tutor_explain"],
    "skills": ["tutor_sop"],
}
