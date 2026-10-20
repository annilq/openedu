"""能力自述与超范围引导 SubAgent 清单（ADR-0079 / ADR-0097 / ADR-0104 / ADR-0105）。

- ``priority=16``：规则路由时代它必须压过 ``tasks``(14) 的泛词（「查 / 有哪些」），
  否则「你能查什么」类元问题会被 ``requires_tool_data`` 硬失败。ADR-0104 移除规则
  路由后，priority 不再参与「抢词」竞争——16 现仅表示能力清单中排在首位
  （见 agent.py 的呈现顺序；capability 自身不出现在清单里）。
- ``roles=["teacher","student"]``：双端都会问「你能做什么」。
- ``actions=[]``：本 subagent 不接收结构化动作键。
- ``skills=[]``：能力清单由 manifests 投影生成（见 agent.py），不需要 SOP 注入。
- ADR-0104：``triggers`` / ``hints`` 词表随规则路由一并删除，「你能做什么」类
  元问题由 LLM / 决策模型按能力清单路由到本业务。
- ADR-0105：``fallback_guide=True``——策略原语（决策模型 / LLM 分类）均不决策
  （都没有命中）时，由本业务接住并提示「自身能做什么」，而不是静默把消息塞给
  某个执行体（tutor 不再作兜底，必须被模型显式路由到）。契约测试守护「至多一个
  业务声明 + 双端可见」。
"""
from __future__ import annotations

MANIFEST = {
    "business": "capability",
    "name": "能力自述",
    "description": "说明助手能做什么、不能做什么，并给出可点方向；不调用模型，返回服务端固定清单。",
    "roles": ["teacher", "student"],
    "priority": 16,
    # 无命中引导（ADR-0105）：都没有命中时由本业务给出能力引导。
    "fallback_guide": True,
    "actions": [],
    "skills": [],
    # 输入 schema（ADR-0095）：能力自述不接收输入，返回服务端固定清单。空列表即无槽位。
    "input_schema": [],
}
