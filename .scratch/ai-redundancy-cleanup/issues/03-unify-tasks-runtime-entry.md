# T03 — 抽取共享 `invoke_subagent` 缝，让结构化出题也过路由/安全闸门（候选 2）

**What to build:** `tasks` 业务当前有两条进入 `AgentRuntime` 的路径且已漂移：聊天路径 `assistant/service.py:453` 先 `rt.decide(...)` 再 `rt.run(business=decision.business, ...)`（`assistant/service.py:646`），经过路由/可见性/虚拟化；结构化出题路径 `features/tasks/service.py:1141-1142` 自建 `deps`+`ctx` 后直调 `rt.run(business="tasks", ...)`，**不经过 `decide`**，因此绕过了与聊天路径相同的闸门。抽一个共享的 `invoke_subagent(...)`（或等价的「带闸 run」入口）让两条路径共用，使结构化出题也走路由/可见性/虚拟化，杜绝静默漂移。

**Blocked by:** 无
**Status:** ready-for-agent

## 决策锚点

- **修法是「共用入口」而非「把 decide 逻辑复制进结构化路径」**：抽绳是本轮全局唯一新增接缝，结构化路径应调用与聊天路径相同的 `invoke_subagent`，而不是各写一套。
- 结构化出题的 `business="tasks"` 是确定的（不像聊天要靠 decide 选），所以共用入口内部可对「已知 business」短路、但仍须过同一道安全/可见性闸。
- 不要为了统一而把聊天路径的「动作直配 / 决策模型 / LLM 分类」三级路由强塞进结构化路径——结构化出题不经自然语言路由，只复用「闸 + 事件流」这一段。
- 抽绳后 `runtime.run` 是否应强制「run 前必经 decide/闸」可作为后续护栏票（见 Backlog），本票只做「两条路径共用同一带闸入口」。

## 验收

- [ ] **两条路径汇入同一道带闸 `run`/`_gate_ok` 缝**：结构化出题路径调 `invoke_subagent(...)`（内部 `decide`→`run`，已知 `business` 短路但仍过闸）；聊天路径 `assistant/service.py` 在可见性断言（`403`）后调 `decide`→`run`——两者最终都经 `_gate_ok` 同一道安全/可见性闸（候选 2 的静默漂移被消除）。
  - 注：聊天路径并非字面调用 `invoke_subagent`，而是与结构化路径共享 `run`/`_gate_ok` 这一唯一带闸 seam；本票目标是「过同一道闸」，而非「字面同一函数名」。
- [ ] 两条路径发出的事件流都经过同一道安全/可见性闸（新增断言验证：结构化出题路径产生的事件在「是否过闸 / 闸拦截产出 `INPUT_UNSAFE`」上与聊天路径一致）
- [ ] 既未知 `tasks` 流式出题契约（`GeneratedQuestion` 形状、落库 `tasks/service.py:616-633` 优先用前端回传 `scene_spec`）不变
- [ ] `action_not_visible` 必须显式产出 `NOT_VISIBLE` 错误帧，不得误标为 `INPUT_UNSAFE`（ADR-0081 §2.3，代码评审回归项，已加回归测试锁住）
- [ ] `tests/ai/`、`tests/api/routes/test_tasks_generate.py` 全绿；新增两路径「过闸一致性」+ `NOT_VISIBLE` 回归测试
- [ ] `ruff` 改动文件净
