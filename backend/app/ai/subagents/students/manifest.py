"""人群域 SubAgent 清单（ADR-0097）。

triggers 收「名单 / 班里 / 名下 / 孩子们」这类**纯人群**问句；与 tasks 的
边界：带学情语境的（「小明错题多吗」）归 tasks——那边工具更全，且聚合问题
不应在名单域断掉。classes 不进 AI（SPEC Out of Scope）。
"""
from __future__ import annotations

MANIFEST = {
    "business": "students",
    "name": "学生名单助手",
    "description": "列出当前账号可见的学生（教师＝名下全部；学生＝自己）。",
    "roles": ["teacher", "student"],
    "triggers": [
        "哪些学生", "有哪些学生", "我的学生", "几个娃", "哪些娃", "有哪些娃", "我的娃",
        "我班", "班里", "名下", "孩子们", "娃们", "学生名单", "多少个学生",
    ],
    "hints": ["学生", "名单"],
    # 路由优先级：低于 tasks(14) / question(12)，高于 tutor(-10 兜底)。
    "priority": 10,
    "actions": [],
    "skills": [],
    # 无槽位：名单查询无参数。
    "input_schema": [],
}
