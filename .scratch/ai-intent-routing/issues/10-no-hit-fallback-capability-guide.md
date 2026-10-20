# 10: 无命中兜底改为能力引导（tutor 显式化，ADR-0105）

> 标签：`ready-for-agent`
> 来源对话：2026-10-20 用户定调「tour(tutor) 也需要显式触发，不作为兜底逻辑，都没有命中则提示自身能力引导」
> 关联：ADR-0105（本票决策记录）；ADR-0104（§2.1 兜底子句由本票取代）、ADR-0079/0097（capability 能力自述，零 LLM 固定清单）、ADR-0081（动作直配不受影响）、ADR-008（学生 TutorLog 随之只在显式 tutor 轮落库）；ticket 09（rule 移除，本票在其兜底语义上再收一刀）

**What to build:** 把「都没有命中」（策略原语——决策模型 / LLM 分类——均不可用或不决策）的落点从 **tutor（可见集 priority 最小者）** 改为 **能力引导（capability）**：所有执行体（tasks / tutor）必须被模型显式路由到，不再有任何执行体充当隐式兜底。实现用**声明式清单字段**而非内核硬编码：`SubAgentManifest` 新增 `fallback_guide: bool = False`，capability manifest 声明 `True`；`runtime._fallback_business` 取可见集中声明了该字段的业务，无声明（或对当前角色不可见）时才退到 priority 最小者作最后防线（当前拓扑不可达，仅为将来清单变化保住「路由永不返回 None」）。

**Blocked by:** 09（rule 整体移除 + 兜底语义已由 ADR-0104 建立；本票改其落点）

**Status:** `ready-for-agent`（本地草稿；GitHub 未登录，待 `gh auth login` 后建 issue 打此标签）

## Problem Statement

ADR-0104 之后兜底 = 可见集中 priority 最小者 = tutor(-10)。问题：

1. **tutor 成了隐式入口**：它从未被「选择」，只是数值最小。路由模型超时、语法错乱的消息、「随便聊聊」全都静默得到一段伴学讲解，而其中很多本应得到「你能做什么」的引导。执行体被兜底语义绑死，显式路由反而成了例外。
2. **兜底与显式路由不可区分**：`routed_by="default"` 与 `"llm"` 的差别只存在于 `extra`，用户视角下「模型选了 tutor」与「没得选落了 tutor」完全同形。

## Solution

1. **清单层**：`SubAgentManifest` 新增 `fallback_guide: bool = False`（`registry.py` 解析），语义＝「策略原语均不决策时由本业务接住并给出自身能力引导」；capability manifest 声明 `True`（零 LLM、返回服务端固定「职责边界 + 你可以让我：…」清单，ADR-0079/0097 的现成载体）。
2. **路由层**：`runtime._fallback_business(visible)` = 可见集中声明了 `fallback_guide` 的业务；无声明/不可见 → `min(priority)` 作最后防线；无可见集 → `None`（既有语义）。`_fallback_decision` / `decide` docstring 同步。
3. **语义纯化**：tutor / tasks 的 `priority` 注释去掉「兜底助手」表述，只保留「能力清单呈现顺序」。
4. **不动**：动作直配（ADR-0081）、策略原语（decision / llm）、`POST /tasks/generate`、前端（run_trace 已有 `'capability' => '能力自述'` 映射）。

## User Stories

1. 作为用户，当路由模型都不可用（都没有命中）时，我希望收到「你能做什么」的能力引导，而不是一段可能答非所问的讲解。
2. 作为用户，我希望伴学答疑只在模型判断该由它处理时出现，而不是成为所有未命中消息的默认垃圾桶。
3. 作为维护者，我希望「谁是引导业务」是清单里的显式声明（`fallback_guide`），内核不硬编码业务键。
4. 作为维护者，我希望契约测试守护「至多一个业务声明无命中引导 + 双端可见」——否则该角色的不命中会静默退化成执行体兜底。
5. 作为维护者，我希望没有声明时的最后防线（priority 最小者）仍在，保住「路由永不返回 None」。
6. 作为教师，我希望「你能做什么」继续由模型显式路由到能力自述（declarative 显式触发），不只在不命中时出现。
7. 作为学生，我希望不命中时同样得到能力引导（capability 双端可见）。
8. 作为维护者，我希望学生端 TutorLog 只在显式 tutor 轮落库（不命中轮不再产生伴学日志）。

## Implementation Decisions

- **声明式字段而非内核硬编码**：`fallback_guide` 让「谁是引导业务」随清单走，契约测试守护唯一性与双端可见；内核保持业务无关（分层不变量）。
- **不用 priority 数值重新指定**（capability 改 −20）：会把「清单呈现顺序」与「无命中落点」耦合进同一个数字，将来新业务数值更低就静默接管兜底；且 capability 的 priority 当前惰性（自身不出现在清单里），改它留谜。
- **最后防线保留 min(priority)**：ADR-0105 明确当前拓扑不可达；删除它会破坏「永不返回 None」，而 None 在 `run` 里是 INPUT_UNSAFE 错误帧（「没有可用助手」会被说成「输入不适当」）。
- **`routed_by="default"` 语义收紧**：从此稳定等价于「都不命中 → 能力引导」，可观测性提升。

## Testing Decisions

- **兜底回归表翻转**：`ROUTING_FALLBACK_REGRESSION`（8 句）从断言 tutor 改为断言 `capability` + `routed_by="default"`——同时锁「规则确已移除」与「tutor 不再兜底」。
- **两层合成测试**（`test_runtime_abstractions`）：声明业务优先于 priority 最小者（与数值无关）；无声明时的最后防线；可见集边界（声明业务对角色不可见则跳过）。
- **新契约**（`test_capability_subagent`）：全清单至多一个 `fallback_guide` 声明、且就是 capability、双端可见。
- **端点测试显式化**：`test_student_tutor_ask_returns_answer_and_logs` 加 `fake_llm.route_to = "tutor"`——tutor 显式路由才落 TutorLog；不声明落点的学生轮（如会话归属测试）只关心归属不关心 kind，注释更新。

## Out of Scope

- 不改策略原语（decision / llm）与 `AI_ROUTING_STRATEGY`。
- 不给 LLM 路由 schema 加「none」选项（模型显式选 capability 已覆盖元问题；不命中由兜底负责）。
- 不改前端（kind 映射已存在）。
- 不动 `POST /tasks/generate` 与结构化出题链路。
- 不实现「连续多轮 default 才给引导」等有状态兜底（用户明确否决方向）。

## Further Notes

- **验证**：`tests/ai` 355 passed（+2 新契约/合成测试）；`tests/api/routes/test_assistant.py` + `tests/features/assistant` 100 passed；全量后端 1003 passed / 2 skipped / 1 failed（`materials test_empty_text_422` 已知环境性红，与 main 基线一致）；ruff 我改的文件全净（6 个既有债经 `git show HEAD:` 对照确认不动）。
- **已知代价（用户接受）**：路由模型长时间不可用时，真实问题也只会得到能力引导；模型恢复后自动回归显式路由。
- **提交**：分支 `ticket/08-decision-routing`，接在 `20a77a0`（rule 移除）之后。
- **发布**：本地写本文件 + 更新 `INDEX.md`；GitHub 待 `gh auth login` 后执行
  `gh issue create --title "T10 — 无命中兜底改为能力引导（tutor 显式化，ADR-0105）" --body-file .scratch/ai-intent-routing/issues/10-no-hit-fallback-capability-guide.md --label ready-for-agent`

## 验收（由 User Stories 派生）

- [x] `SubAgentManifest.fallback_guide` 字段存在并被 manifest 解析。
- [x] capability 声明 `fallback_guide=True`；tutor / tasks 无声明且注释去兜底表述。
- [x] 都不命中（8 句回归表 + provider 不可用/畸形/不可见）恒落 capability / `routed_by="default"`。
- [x] 声明业务优先于 priority 最小者（合成测试）；无声明时的最后防线与可见集边界仍在。
- [x] 契约：至多一个声明 + 双端可见。
- [x] 学生伴学用例显式 `route_to="tutor"` 后 TutorLog 落库；不声明落点不再产生 tutor 行为。
- [x] `tests/ai` 355 passed；全量 1003 passed / 2 skipped / 1 环境性红。
- [x] ADR-0105 落库；ADR-0104 §2.1 打取代标注。

## 纪律

- **内核不硬编码业务键**：无命中落点只能来自 manifest 的 `fallback_guide` 声明。
- **执行体不做兜底**：tutor / tasks 必须被模型显式路由到；最后防线（min priority）仅是无声明时的防御，当前拓扑不可达。
- **契约测试守护声明唯一性 + 双端可见**，防止「该角色不命中静默退化成执行体兜底」。
- 测试里文本路由的确定性只能来自路由桩显式表态（`route_to` / `RoutingFakeProvider`），替身不猜。
