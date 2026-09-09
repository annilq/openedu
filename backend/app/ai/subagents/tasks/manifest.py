"""任务查询 SubAgent 清单（ADR-0024）。

仅家长可见（roles: parent）；triggers 覆盖「查看/列出/查询任务题目」意图。
依赖 shared_tool ``list_tasks``（app/ai/tools）。
"""
from __future__ import annotations

MANIFEST = {
    "business": "tasks",
    "name": "任务查询",
    "description": "列出家长名下的草稿任务及其题目。",
    "roles": ["parent"],
    "triggers": [
        "任务", "作业", "查看任务", "列出任务", "查询任务", "任务题目",
        "有哪些题", "我的任务", "草稿任务",
    ],
    "tools": ["list_tasks"],
    "skills": [],
}
