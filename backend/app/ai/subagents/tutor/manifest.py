"""伴学 SubAgent 清单（ADR-0024）。

双端通用（roles: teacher + student，ADR-0026）：学生端只暴露伴学答疑，不暴露出题/答案。
triggers 覆盖「为什么/怎么/讲解/不会」等问答意图。
"""
from __future__ import annotations

MANIFEST = {
    "business": "tutor",
    "name": "伴学答疑",
    "description": "针对学生的提问给出适龄、纯学习相关的讲解。",
    "roles": ["teacher", "student"],
    "triggers": [
        "为什么", "怎么", "怎样", "讲解", "不会", "不懂", "是什么意思",
        "教我", "帮我讲", "解答", "原理", "如何", "为什么是",
    ],
    # 无兜底词：规则与启发式都没命中时，优先级最低者（本业务）接住（ADR-0030）
    "hints": [],
    "priority": -10,
    # 结构化动作（T06）：课件练习求「提示」与待判定态消费后的判定/讲解，本质上都是
    # 「就这道题说话」，归属伴学答疑。二者方向由服务端在信号归一化阶段产出，不再事后改判。
    "actions": ["courseware_hint", "quiz_judge"],
    "skills": ["tutor_sop"],
}
