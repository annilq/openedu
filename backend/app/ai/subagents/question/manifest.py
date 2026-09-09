"""出题 SubAgent 清单（ADR-0024）。

business 即路由键；triggers 为意图路由规则匹配词；roles 限定可见角色
（出题仅家长端，ADR-0026 安全：娃娃端永不暴露出题/答案）。
"""
from __future__ import annotations

MANIFEST = {
    "business": "question",
    "name": "出题助手",
    "description": "根据科目、年级、题型与数量生成题目题卡（含选项与解析）。",
    "roles": ["parent"],
    "triggers": [
        "出题", "出几道", "出道", "出题目", "来几道", "生成题", "题目",
        "测验", "考考", "练", "给我出", "帮我出",
    ],
    "tools": ["generate_question"],
    "skills": ["question_sop"],
}
