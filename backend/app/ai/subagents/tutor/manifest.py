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
    # 结构化动作：伴学答疑不再声明任何动作键（ADR-0089）。课件提示由 courseware 上下文
    # 触发、判断题判定由对话历史里的题卡驱动，均不经服务端动作键与待判定态。
    "actions": [],
    "skills": ["tutor_sop"],
    # 输入 schema（ADR-0095）：伴学答疑的核心输入就是用户消息本身（question_text）。
    # subject/grade/knowledge_point 为 optional，命中上下文（课件/知识点下钻）即补全，不追问。
    "input_schema": [
        {"name": "question_text", "type": "string", "required": True,
         "prompt": "你想问什么？（把问题发给我）", "source": "text"},
        {"name": "subject", "type": "enum", "required": False,
         "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
        {"name": "grade", "type": "int", "required": False, "min": 1, "max": 9, "source": "both"},
        {"name": "knowledge_point", "type": "string", "required": False, "source": "both"},
    ],
}
