"""出题 SubAgent 清单（ADR-0024）。

business 即路由键；triggers 为意图路由规则匹配词；roles 限定可见角色
（出题仅家长端，ADR-0026 安全：娃娃端永不暴露出题/答案）。

与 ``query`` 的边界（ADR-0033 决策 6）：本业务触发器含泛词「题目」，凡带
「任务 / 作业 / 错题 / 复习」等查询语境的问句由 ``query``（priority=12）优先接住；
**「出题 / 来几道 / 生成题」才是本业务的意图**。
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
    # 启发式兜底词（规则未命中时用，ADR-0030）
    "hints": [
        "出题", "出几道", "出道", "出道题目", "出题目", "题目", "测验",
        "考考", "练", "生成题", "来几道", "给我题",
    ],
    # 路由优先级：低于 query（"任务题目" 归 query，ADR-0033 决策 6），高于 tutor（兜底）
    "priority": 0,
    "skills": ["question_sop"],
}
