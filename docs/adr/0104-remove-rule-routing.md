# ADR-0104 移除规则路由：业务选择完全由模型按上下文 + 能力清单决定

- 状态：已采纳
- 日期：2026-10-20
- 关联：ADR-0098（二执行体收敛；`intent_schemas` 子意图分组随之删除）、ADR-0099（已确认规格跨轮回灌；聊天链路 specs 注入随之删除）、ADR-0100（缺槽追问一句话引导；机制保留、聊天层暂不可达）、ADR-0101（正则触发词；整条 `trigger_patterns` 随之删除）、ADR-0081（动作直配，不受影响）、ADR-0095（schema 驱动槽位引擎，机制保留）
- 实现：分支 `ticket/08-decision-routing`，提交 `4fcc686`（决策模型）+ `d8a9ed0`（可切换 LLM 分类）+ 本轮（rule 整体移除）

## 1. 背景

两个已确认的路由故障，根因都不在「词表少了几个词」，而在**规则路由的匹配方式**：

1. **首轮 miss**（ADR-0101 已修）：`_rule_match` 是子串包含，「出道」命不中「出一道选择题」。
   修法（正则词族）本身成立，但它承认了一个事实：**任何词表 / 正则都是在枚举用户的说法**。
2. **续接落 tutor**（2026-10-20 实测，第二个 trace）：路由对每条消息**无状态独立分类**，
   首轮出题后用户改口「数学」，被独立路由到伴学答疑，出题态丢失。根因是
   `runtime.decide` 只传当前文本、不传会话上下文。

与此同时，架构零件已齐：`DecisionModel` 端口 + `LayaDecisionModel` 适配器（T08，
`4fcc686`）、通用 LLM 结构化分类 `classify_llm` + 策略开关 `AI_ROUTING_STRATEGY`
（`d8a9ed0`）、`decide(history=…)` 全量上下文透传、manifest 的 `name/description/actions`
即能力清单。用户据此定调：**不根据规则分类路由，而是直接用 LLM 分类，每一轮保持所有
消息上下文，按 agent 能力路由**；并要求**去掉 rule 决策相关功能**。

## 2. 决策

**规则（关键词 / 启发式）路由整体移除，业务选择完全由模型按「对话上下文 + 能力清单」决定。**

### 2.1 路由层（agent_core）

- `router.py`：删除 `classify` / `Classification` / `_rule_match` / 启发式兜底 / 归一化辅助；
  保留 `IntentSignal` / `match_action`（动作直配，ADR-0081）与内核 stdlib 辅助
  `_build_routing_state` / `_capability_text`（决策模型与 LLM 分类共用）。
- `runtime.py`：策略原语只剩 `decision`（Laya-multilingual）与 `llm`（`classify_llm`），
  `_STRATEGY_ORDER`：`llm=[llm]`、`decision=[decision,llm]`、`auto=[decision,llm]`（默认）。
  两者均不可用 / 不置信 → **兜底助手**：可见集中 `priority` 最小者（生产拓扑即 tutor），
  路由永不返回 `None`（安全闸门拦截除外）。
- `RouteDecision` 删除 `trigger` 字段（规则命中词的唯一出口，随规则一并下线）。

### 2.2 清单层（manifest）

- `registry.py`：`SubAgentManifest` 删除 `triggers` / `hints` / `trigger_patterns`
  三个规则匹配专用字段及其编译逻辑；`priority` 语义收缩为「兜底助手 + 能力清单呈现顺序」，
  不再参与任何「抢词」竞争。
- 三个 manifest（tasks / tutor / capability）删除上述字段；tasks 的 `intent_schemas`
  （出题子意图分组）一并删除——它的唯一选择器就是 `trigger`。

### 2.3 出题引导链路（service.py）

`trigger` 消失后，靠它选子意图的整条引导链随之关闭（用户明确选择「一并移除，纯 LLM 生成」）：

- `_resolve_input_schema(business)` 只返回默认 `input_schema`（全 optional）；
- 删除 `_intent` 两本账、`_business_triggered`（ADR-0099 闸门）、`ctx.extra["specs"]`
  聊天侧注入、「已确认规格」汇总帧；
- 聊天链路出题 = **纯 LLM 自由文本生成**（history 每轮全量进上下文，规格由模型自行重建）；
- 按规格的结构化出题仍由 `POST /tasks/generate`（`ctx.extra["specs"]`）承载，不受影响；
- 缺槽预检机制（`fill_slots` / `clarify_sentence` / 澄清帧 / DONE 补发）作为**通用槽位引擎
  保留**——现有 manifest 全 optional 故聊天层暂不可达，将来任何业务声明必填槽即自动生效。

## 3. 后果

- **行为变化**：文本路由不再有确定性关键词命中——生产由真实模型判定，测试由路由桩显式
  声明落点；无任何模型时一律兜底 tutor（`routed_by="default"`）。
- **UX 降级（已接受）**：聊天出题不再有「请选科目/年级/题型」引导澄清与规格回显，
  改纯 LLM 生成；图形化/结构化题卡在聊天链路改由模型自由产出。
- **槽位存储简化**：`conversation.slots` 从 `business:intent` 两本账回归每 business 单键；
  历史 `tasks:generate` / `question` 键的旧行不读、无需迁移。
- **测试面迁移**：规则语义测试（路由回归表、词表契约、「出 N 道」族、词序不变量）随规则
  删除；新增/改写的是机制测试（策略切换、兜底、history 透传、动作直配）+ 新行为锁定
  （无模型恒兜底、聊天不澄清/不注入 specs/不发汇总帧）+ 合成必填槽守护的澄清路径。
- **澄清路径覆盖率缺口（已知）**：726dba9 的「澄清轮补发 DONE」回归改由 `required_slots`
  合成 schema 在端到端层守护；`clarify_sentence` 话术由纯函数测试覆盖。

## 4. 备选（否决）

- **保留 rule 作最终兜底**（T08 当时的 `auto=decision→rule`）：兜底语义由「关键词猜」
  决定，续接短消息仍会落错业务；且 rule 留着就意味着词表纪律、契约测试、正则族
  （ADR-0101）全部要继续维护。用户明确要求去掉。
- **子意图改在 service 内复用 manifest 词表扫描得出**（保留出题引导）：等于把规则匹配
  复制到第二处，两份口径迟早漂移；且引导链的澄清/汇总/specs 注入本就是 ADR-0098
  子意图分组的下游，拆开留一半最不干净。
- **LLM 回传子意图**（扩展 `RoutingDecision` 加 `intent` 字段）：完全走 LLM、零关键词，
  但要改 schema + 路由 + 端点 + 全部桩，且出题引导的 UX 收益不值得这轮成本。
- **删除整个槽位引擎（ADR-0095 机制）**：超出「去掉 rule 决策」的范围；结构化端点仍依赖
  `merge_spec_layers` / `specs_from_context`，通用澄清机制对将来声明必填槽的业务直接可用。

## 5. 守卫

| 测试 | 锁什么 |
|---|---|
| `tests/ai/test_agent_runtime.py::test_decide_without_models_falls_back_to_tutor` | 无任何路由模型时恒兜底（规则确已移除，八句实测输入全落 tutor） |
| `tests/ai/test_llm_routing.py` / `test_decision_model_routing.py` | 策略切换（llm / decision / auto 经 llm）、不可用 / 畸形 / 不可见 → 兜底 |
| `tests/ai/test_runtime_abstractions.py::test_decide_falls_back_to_lowest_priority_business` | 兜底 = 可见集中 priority 最小者（含角色过滤） |
| `tests/ai/test_intent_routing_contract.py` | 动作直配四件套（唯一性 / 可见 / 不可见显式 / 未知动作回落文本路由）不变 |
| `tests/features/assistant/test_slot_filling_integration.py`（真实配置组） | 聊天链路恒放行：不澄清、不注入 specs、不发汇总帧；槽位按 business 单键落库 |
| 同文件 `required_slots` 组 | 通用澄清路径（追问帧 / DONE 补发 / 落库去回 / 回放气泡白名单）仍工作 |
| `tests/features/assistant/test_slot_context_carryover.py` |  specs 聊天侧恒不回流（续话 / 换规格 / 长会话 / 无关话）；`merge_spec_layers` 结构化语义不变 |
