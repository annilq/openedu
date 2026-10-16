"""能力自述与超范围引导 SubAgent 清单（ADR-0079 / ADR-0097）。

- ``priority=16``：高于 ``tasks``(14) / ``question``(12) / ``students``(10)。必须压过
  它们的泛词（「查 / 有哪些」），否则「你能查什么」类元问题会被 ``requires_tool_data``
  硬失败。写意图不冲突：``tasks`` 的写触发词是「创建任务」等高精度短语，与能力自述
  问句无交集（ADR-0097 起 guide 删除，写意图由 tasks 承接）。
- ``roles=["teacher","student"]``：双端都会问「你能做什么」。
- ``triggers`` 只收完整短语，``hints`` 留空——宁可漏给 tutor 兜底也不误抢其它意图
  （路由是「词是否被包含」匹配，泛词命中面过宽）。
- ``actions=[]``：本 subagent 不接收结构化动作键。
- ``skills=[]``：能力清单由 manifests 投影生成（见 agent.py），不需要 SOP 注入。
"""
from __future__ import annotations

MANIFEST = {
    "business": "capability",
    "name": "能力自述",
    "description": "说明助手能做什么、不能做什么，并给出可点方向；不调用模型，返回服务端固定清单。",
    "roles": ["teacher", "student"],
    "triggers": [
        "你能做什么", "你会什么", "你能帮我什么", "你有什么功能", "有什么功能",
        "怎么用你", "你是谁", "你是什么", "你能干什么",
    ],
    # 留空是有意的：能力自述需要高精度，启发式兜底会把查询/讲解意图一并抢来。
    "hints": [],
    "priority": 16,
    "actions": [],
    "skills": [],
    # 输入 schema（ADR-0095）：能力自述不接收输入，返回服务端固定清单。空列表即无槽位。
    "input_schema": [],
}
