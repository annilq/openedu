# 04 · slot filling 意图分组

Blocked by: 03

## 内容

- **agent_core/router.py**：`_rule_match` 返回 `(business, trigger)`；`classify` 改返回
  `Classification(business, trigger, level)`（level ∈ rule/heuristic/fallback，便于测试
  断言路由层级）；`match_action` 路径 trigger=None。`RouteDecision`（runtime.py）增
  `trigger: str | None = None`；`decide` 透传。
- **service.py 预检**：
  - `_load_input_schema(business, trigger)` → 按 manifest `intent_schemas` 解析意图
    （trigger 命中某组 → 该组 schema，intent=组名；否则默认 schema，intent=None）。
  - 槽位存储键：默认 `business`，子意图 `f"{business}:{intent}"`（历史 `question` 键
    的旧行不读，无需迁移）。
  - specs 注入条件 `intent == "generate"`（原 `business == "question"`）。
- **契约测试**（test_intent_routing_contract.py 或新文件）：`intent_schemas[*].triggers ⊆
  MANIFEST["triggers"]`；分类器返回结构与启发式层级。

## 验收

- 多轮出题澄清链不变（缺 grade → 只问 qtype → 出题 + 「已确认规格」汇总帧）。
- 「今天有什么作业」「我的错题」不触发任何澄清。
- 槽位两本账：出题槽（subject/grade/qtype）与学情槽（count 默认 3）不互冲。
