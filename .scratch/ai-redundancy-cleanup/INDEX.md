# AI 子系统冗余/过载设计清理

> 来源审查：`architecture-review-20261020-2047.html`（由 unslop / codebase-design / improve-codebase-architecture 三 skill 驱动，对 AI 助手子系统做冗余/过载扫描）
> 驱动 skill：unslop（去 AI 腔）、codebase-design（浅模块 / 透传层 / 删除测试）、improve-codebase-architecture（grill 决策树）
> 相关 ADR：`0081`（动作直配）、`0088`（admin + 运行轨迹 + 脱敏破窗）、`0098`（二执行体收敛，删 question/students subagent）、`0104`（移除规则路由）、`0105`（无命中兜底=能力引导）
> 术语以 `CONTEXT.md` 为准。范围：AI 子系统 5 处冗余/过载候选，一次写全。

一句话：**AI 子系统没有「过载的主智能体」（`AgentRuntime` 是零 LLM 大脑的薄编排器），真正的冗余集中在边缘——假工具帧、双 runtime 入口、双路由适配器、两个同名 `ai` 包、死代码壳。**

## 问题陈述

用户观察到 AI 子系统近期围绕 ADR-0097→0105 反复改动路由与执行体，怀疑存在「主智能体过载 / 可移除 subagent / 直接调工具」的冗余设计。审查结论：

- **没有过载的主智能体**：`AgentRuntime`（`agent_core/runtime.py`）不持有 LLM 大脑，决策委托给路由适配器，每个 SubAgent = 一次 LLM 调用。因此「整体移除 subagent、直接调工具」不可行；subagent 类可保留为「帧编排层」，但不得伪造接缝。
- **5 处真实冗余/过载**（全部代码核实，见实测底稿）：(1) TutorSubAgent 发出不存在的 `tutor_explain` 工具帧；(2) `tasks` 业务有两条 `rt.run` 入口且已漂移；(3) Laya 决策模型与 `classify_llm` 两套并行路由适配器，且 LLM 提示词里硬编码了 ADR-0104 已删除的路由规则；(4) `app/ai`（内核）与 `app/features/ai`（调试 REST）两个同名包撞车；(5) ADR-0098 删掉的 question/students subagent 残留空壳目录 + 3 处陈旧「question subagent」字符串。

## 方案

逐候选清理，遵循「删除测试」：凡是不被任何调用方依赖、删去后不在他处重现复杂度的代码，一律删除；保留的 subagent 类明确为「帧编排层」，停止伪造工具接缝。5 个候选相互独立，按风险序（安全壳 → 低风险重命名 → 帧修正 → 适配器去重 → 安全闸门统一）执行，每个候选一张 ticket。

## 用户故事

1. As an AI 子系统维护者，I want TutorSubAgent 不再发出「假装调用了工具」的伪帧，so that 读代码/轨迹时不会被误导以为走过了工具接缝。
2. As an AI 子系统维护者，I want 结构化出题与聊天答疑走同一条带安全闸门/路由的 runtime 入口，so that 两套路径不会静默漂移、结构化出题不再绕过可见性/虚拟化。
3. As an AI 子系统维护者，I want 路由只由一套机制裁决（决策模型或 LLM 分类二选一，靠策略开关），so that LLM 提示词里不再偷偷复活 ADR-0104 已删除的路由规则。
4. As a 新接手开发者，I want 智能体内核包与 AI 调试 REST 包不再都叫 `ai`，so that import 时不混淆、目录导航清晰。
5. As an AI 子系统维护者，I want 删掉 ADR-0098 残留的 question/students 空壳目录与陈旧字符串，so that 仓库不留死代码、文档与 business 键（tasks）一致。

## Tickets（依赖序，blockers first）

| ID | 标题 | Blocked by | Status |
|----|------|-----------|--------|
| 01 | 删除 question/students 空壳目录 + 陈旧「question subagent」字符串（候选 5） | — | ready-for-agent |
| 02 | TutorSubAgent 停止伪造 `tutor_explain` 工具帧（候选 1） | — | ready-for-agent |
| 03 | 抽取共享 `invoke_subagent` 缝，让结构化出题也过路由/安全闸门（候选 2） | — | ready-for-agent |
| 04 | 路由适配器去重：剥离 `classify_llm` 提示词里硬编码的已删规则（候选 3） | — | ready-for-agent |
| 05 | 重命名 `app/features/ai` → `app/features/agent_debug`（候选 4，内核 `app/ai` 不动） | — | ready-for-agent |

**依赖说明**：5 票文件集互不相交（01=空壳+字符串；02=tutor/agent.py；03=features/tasks/service.py+agent_core/runtime.py；04=agent_core/adapters/*+router.py；05=app/features/ai/*+app/api/main.py），均无硬 blocker，可各自独立分支。推荐风险序执行：01→05→02→04→03。

## 决策锚点

- **SubAgent 类可留作「帧编排层」，但不得伪造工具**：TutorSubAgent 的真活（流式讲解 + 交互演示 + 溯源）是实打实的，删掉它复杂度不在调用方重现 → 外壳保值；唯有 `tutor_explain` 的 TOOL_CALL/RESULT 帧是戏服（无对应 ToolSpec、不进真实 tool loop），必须去掉或改为诚实的步骤标签。
- **结构化出题必须过同一道闸**：`features/tasks/service.py:1141` 直调 `rt.run(business="tasks")` 绕过了 `rt.decide`（`assistant/service.py:453`），意味着它不经过路由/可见性/虚拟化。修法是抽 `invoke_subagent(...)` 让两条路径共用，而不是把 decide 的逻辑复制过去。
- **路由规则已在 ADR-0104 整体移除**：`llm_route.py:37-45` 的 `ROUTING_SYSTEM_PROMPT` 仍硬编码 3 条编号规则（「沿用上一轮助手」「学生作答路由伴学答疑」「只输出业务键原文」），与 ADR-0104「不根据规则分类路由」正面冲突。适配器去重 ≠ 删掉 LLM 分类器，而是把规则文本从提示词里剥离，路由完全交给清单 + 上下文。
- **重命名只动小包**：`app/features/ai`（调试/脱敏 REST，仅 6 处引用）与内核 `app/ai`（~55 处引用）撞名。重命名前者 → `app/features/agent_debug`，URL 前缀 `/ai/debug` 由 router 固定、与包名无关，故 API 不变；**绝不重命名内核 `app/ai`**（爆炸半径 55 处）。
- **删除测试优先**：候选 1/5 是纯删除，先落以验证「仓库允许删除、CI 仍绿」的纪律；候选 3 的 `invoke_subagent` 抽绳是全局唯一新增接缝。

## 实测底稿（实施前不可省，别重新猜）

全部于 `git branch = main`、2026-10-20 实测：

| 候选 | 发现 | 证据 |
|---|---|---|
| 1 | TutorSubAgent 发出 `tutor_explain` 帧但无对应 ToolSpec | `app/ai/subagents/tutor/agent.py:112-113`（`tc=self._tool("tutor_explain",...)` + `yield tc.call`）、`:145`（`yield tc.result(...)`）；全仓仅 `docs/adr/0101` 一处文档提及，无任何测试/前端断言该帧 |
| 2 | `tasks` 业务两条 `rt.run` 入口 | 聊天：`app/features/assistant/service.py:453`（`decision=await rt.decide(...)`）→ `:646`（`rt.run(..., business=decision.business, ...)`）；结构化：`app/features/tasks/service.py:1141-1142` 自建 `deps`+`ctx` 直调 `rt.run(business="tasks", ...)`，不经过 `decide` |
| 3 | 两套并行路由适配器 + LLM 提示词硬编码已删规则 | `agent_core/adapters/llm_route.py`（`classify_llm` + `RoutingDecision` schema）；`agent_core/adapters/laya.py`（`LayaDecisionModel`，仅 `laya-multilingual`）；`llm_route.py:37-45` 硬编码 3 条编号规则；策略选通见 `agent_core/runtime.py` 的 `AI_ROUTING_STRATEGY`（`llm=[llm]`/`decision=[decision,llm]`/`auto=默认`）|
| 4 | 两个同名 `ai` 包 | 内核 `app/ai/`（~55 处 `from app.ai` 引用，承载 subagents/tools/runtime 集成）；REST `app/features/ai/`（仅 6 处引用：`app/api/main.py:3` 挂载 + 包内 5 处自引；含 `masking.py`/`repository.py`/`schemas.py`/`router.py`，服务 `/ai/debug/*` 轨迹与脱敏，ADR-0088）|
| 5 | question/students 空壳 + 陈旧字符串 | `app/ai/subagents/question/`、`app/ai/subagents/students/` 仅剩 `__pycache__/*.pyc`（源 `.py` 已被 ADR-0098 删除，已 `grep` 确认零 import）；3 处陈旧「question subagent」：`app/features/tasks/router.py:81`、`app/features/tasks/schemas.py:63`、`tests/api/routes/test_tasks_generate.py:5`（business 键实为 `tasks`）|

## 测试缝

- **全局唯一接缝：`AgentRuntime.decide` / `rt.run` 入口**。所有路由/可见性断言打在 `decide` 返回值与 `run` 发出的事件流上，沿用 `tests/ai/` 既有用例形状，端点与 DB 层不测。
- **好测试的判据**：只断言「给定信号 + 角色 → 路由/事件是什么」，**不断言内部走了哪一级、emit 了哪个 TOOL_CALL 帧名**，这样帧名/路由机制以后怎么重排测试都不碎。
- 各票测试重点：
  - 01：删壳 + 改字符串后全量 `pytest` 绿；`grep "question subagent"` 归零。
  - 02：tutor 事件流仍含讲解 delta + 交互演示 + 溯源；断言流中**不再出现** `tutor_explain` 这个 TOOL_CALL 帧（若保留诚实标签则用新名）。
  - 03：结构化出题的事件流与聊天路径在「是否过闸」上一致（同一条 `invoke_subagent`）；两路径各加一个断言「经过 decide/闸」的测试。
  - 04：路由用例在 `AI_ROUTING_STRATEGY` 两种取值下均不回归；`classify_llm` 提示词快照测试断言不含编号规则。
  - 05：重命名后 `app/api/main.py` 仍能挂载、`/ai/debug/*` 端点 200；全仓 `grep "app.features.ai"` 归零、`grep "app.features.agent_debug"` 命中 6 处。

## 转 GitHub issue 步骤（待登录）

1. `gh auth login`（或设 `GH_TOKEN`）
2. 按编号 01→05 顺序建 issue（blockers 均为无，按推荐风险序）
3. 全部打 `ready-for-agent` 标签

建 issue 命令模板：
`gh issue create --title "T0N — <标题>" --body-file .scratch/ai-redundancy-cleanup/issues/0N-<slug>.md --label ready-for-agent`

## Backlog（暂不在本轮 5 票内）

- 候选 3 的「彻底合并为单一路由机制」：当前是 `decision` 与 `llm` 二选一（策略开关），prod 跑其一。是否合并为单一扩展点属更大重构，需先有弱意图兜底实测（见 `ai-intent-routing` backlog）。
- 候选 4 若日后内核 `app/ai` 也要改名（如 `app/agents`），是 55 处爆炸半径重构，独立议题。
- `agent_core/runtime.py` 的 `run` 是否应强制「run 前必经 decide/闸」——属候选 3 收口后的护栏，可独立成票。

**Frontier：空。**
