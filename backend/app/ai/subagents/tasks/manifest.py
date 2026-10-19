"""任务学情域 SubAgent 清单（ADR-0097）。

triggers 由两部分组成：

1. **写意图词表**（自 guide 迁入，priority 20 → 14）：「创建 / 布置 / 派发 /
   添加任务」类完整短语。guide 删除后写意图在本域有着落——create_draft 起草、
   确认卡发布，取代原来的固定话术引导。
2. **学情查询词**（自 query 的 triggers 迁入）：「任务 / 作业 / 错题 / 进度 /
   掌握度 / 复习」。

**词表纪律**（沿袭 guide/query 双方针）：路由是「词是否被包含」的匹配，
泛词（``创建`` / ``建`` / ``任务``）会把「查一下我创建过的任务」也拽过来；
写意图只收「动作 + 对象」的完整短语。``hints`` 收查询语境词——启发式兜底
只给查询意图，写意图不兜底（宁可漏给下游也不误抢）。
"""
from __future__ import annotations

MANIFEST = {
    "business": "tasks",
    "name": "任务学情助手",
    "description": (
        "查询任务 / 错题 / 进度 / 掌握度 / 待复习（学生查自己）；"
        "教师还可从题库组建草稿任务（确认后发布）。"
    ),
    "roles": ["teacher", "student"],
    "triggers": [
        # 写意图（自 guide 迁入）：完整短语，防泛词误抢查询
        "创建任务", "创建一个任务", "创建个任务", "创建一份任务", "创建新的任务",
        "新建任务", "新建一个任务", "新建个任务",
        "建个任务", "建一个任务",
        "创建作业", "新建作业", "建个作业", "建一个作业",
        "布置任务", "布置作业", "布置一下",
        "派发任务", "派发作业", "帮我派发",
        "添加任务", "加个任务", "加一个任务",
        # 学情查询（自 query 迁入）
        "任务", "作业", "错题", "错了哪些", "错过的题", "哪些题错",
        "进度", "掌握度", "复习", "待复习", "薄弱", "打卡",
        "学得怎么样", "学习情况", "学情", "今日任务", "我的任务", "任务题目",
        # 学生名单（自 students 域吸收，ADR-0098）：纯人群短语
        "哪些学生", "有哪些学生", "我的学生", "几个娃", "哪些娃", "有哪些娃",
        "我的娃", "我班", "班里", "名下", "孩子们", "娃们",
        "学生名单", "多少个学生",
    ],
    # 启发式兜底词（规则未命中时用）：只收查询语境，写意图不兜底。
    # 「题库」归 question（出题与题库管理），「学生」归 students（人群）——
    # 两域都不在本表，避免兜底层互相抢。
    "hints": [
        "任务", "作业", "练习册", "错题", "复习", "掌握", "进度",
        "查看", "列出", "查询",
    ],
    # 路由优先级：高于 question(12，出题与题库管理)，低于 capability(16)。
    # 写意图靠本优先级接住 guide 原来的拦截位（原 guide=20 压 query=12）。
    "priority": 14,
    # 结构化动作：任务起草不设动作键——创建走自由文本 triggers + slot filling
    # 预检；「按规格出题」仍归 question（task_generate）。
    "actions": [],
    "skills": [],
    # 输入 schema（ADR-0095）：本域槽位。读操作不阻塞（全部 optional）；
    # create_draft 的目标学生必填性由 handler 校验（ToolArgumentError 回灌，
    # 模型转问用户）——预检层只对「结构化规格直配」生效，见 SPEC §2.4。
    "input_schema": [
        {"name": "subject", "type": "enum", "required": False, "default": "",
         "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
        {"name": "grade", "type": "int", "required": False, "min": 1, "max": 9, "source": "both"},
        {"name": "count", "type": "int", "required": False, "default": 3,
         "min": 1, "max": 10, "source": "text"},
    ],
}
