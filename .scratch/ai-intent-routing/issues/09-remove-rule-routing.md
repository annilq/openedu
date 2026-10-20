# 09: 移除规则路由（rule 决策整体下线，ADR-0104）

> 标签：`ready-for-agent`
> 来源对话：2026-10-20 路由重构第七轮——用户定调「不根据规则分类路由，而是直接使用 llm 分类，每一轮对话都保持所有消息上下文，根据 agent 能力路由」后，下令「去掉 rule 决策相关功能」；AskUserQuestion 确认出题引导链（必填槽澄清 + 规格回显）一并移除，走纯 LLM 自由文本生成（明确接受 UX 降级）
> 关联：ADR-0104（本票决策记录）；ADR-0098（`intent_schemas` 子意图分组随之删除）、ADR-0099（specs 聊天侧回灌随之删除）、ADR-0100（缺槽引导机制保留、聊天层暂不可达）、ADR-0101（`trigger_patterns` 整条删除）、ADR-0081（动作直配不受影响）、ADR-0095（槽位引擎机制保留）；ticket 08（决策模型，本票推翻其「规则 classify 保留为兜底 + 离线测试」的纪律）

**What to build:** 把规则（关键词 / 启发式）路由**整体移除**——引擎（`classify`/`Classification`/`_rule_match`/启发式）、策略（`rule` 策略分支）、清单字段（`triggers`/`hints`/`trigger_patterns`）、路由输出（`RouteDecision.trigger`）、以及靠 `trigger` 选子意图的整条出题引导链（`_business_triggered` 闸门、`ctx.extra["specs"]` 聊天侧注入、「已确认规格」汇总帧、`business:intent` 两本账）。移除后业务选择完全由模型按「对话上下文 + 能力清单」决定：策略原语只剩 `decision`（Laya-multilingual）与 `llm`（`classify_llm` 结构化分类），`AI_ROUTING_STRATEGY` 三值切换（`llm=[llm]`、`decision=[decision,llm]`、`auto=[decision,llm]` 默认），两者均不可用/不置信 → **兜底助手**（可见集中 `priority` 最小者，生产拓扑即 tutor，`routed_by="default"`），路由永不返回 `None`。动作直配（ADR-0081）仍排最前，不受影响。

**Blocked by:** 08（决策模型端口 + `decide(history=…)` 全量上下文透传必须先落地；本票在其之上删规则层）

**Status:** `ready-for-agent`（本地草稿；GitHub 未登录，待 `gh auth login` 后建 issue 打此标签）

## Problem Statement

08 落地后链路是 `动作直配 → decision → rule classify → 兜底`，但规则层留着有三个持续成本：

1. **兜底语义由「关键词猜」决定**：decision 不置信时回落 rule，而 rule 对续接短消息（「数学」「三年级」）无任何触发词可命中 → 仍落错业务。续接 bug 的根因（无状态 + 词表枚举）在规则层里并未真正消除，只是被 decision 主路由暂时遮住。
2. **维护税**：词表纪律、`trigger_patterns` 正则族（ADR-0101）、契约测试（词序不变量、「出 N 道」族、词表⊆触发词）全部要继续养；任何词表遗漏都重演「出道 vs 一道」式 miss。
3. **规则是第二份口径**：`intent_schemas`（子意图分组）的唯一选择器就是 `trigger`；规则在，出题引导链（澄清 + 规格回显 + specs 注入）就得在，用户已明确不接受这套引导 UX（「一并移除，纯 LLM 生成」）。

## Solution

三层移除 + 一个新策略拓扑：

1. **路由层（`agent_core`）**：`router.py` 删 `classify`/`Classification`/`_rule_match`/启发式/归一化辅助，保留 `IntentSignal`/`match_action` 与内核 stdlib 辅助 `_build_routing_state`/`_capability_text`（decision 与 llm 共用）；`runtime.py` 删 rule 策略分支，`_STRATEGY_ORDER` 收敛为三值；`RouteDecision` 删 `trigger` 字段。
2. **清单层（manifest）**：`registry.py` 的 `SubAgentManifest` 删 `triggers`/`hints`/`trigger_patterns` 及其编译逻辑；`priority` 语义收缩为「兜底助手 + 能力清单呈现顺序」；tasks/tutor/capability 三个 manifest 删除上述字段，tasks 的 `intent_schemas` 一并删除。
3. **出题引导链（`service.py`）**：`_resolve_input_schema(business)` 只返回默认 `input_schema`（全 optional）；删 `_business_triggered`、`ctx.extra["specs"]` 聊天侧注入、「已确认规格」汇总帧；`conversation.slots` 回归每 business 单键。聊天出题 = 纯 LLM 自由文本生成；按规格的结构化出题仍由 `POST /tasks/generate` 承载。
4. **保留（范围纪律）**：缺槽预检通用机制（`fill_slots`/`clarify_sentence`/澄清帧/DONE 补发，726dba9）——现有 manifest 全 optional 故聊天层暂不可达，由合成必填槽守护，将来任何业务声明必填槽即自动生效；`merge_spec_layers`/`specs_from_context` 结构化语义不变。

## User Stories

1. 作为维护者，我希望规则路由（关键词/启发式/正则/触发词）从代码里彻底消失，而不是留一个「不再被调用」的死层——避免下次有人照着词表继续修 bug。
2. 作为用户，我希望每轮路由都基于完整对话上下文（history 全量进模型 state），续接短消息不再因无触发词而落错业务。
3. 作为用户，我希望出题请求拿到场景化/结构化题卡（由模型自由产出），而不是纯文本讲解。
4. 作为教师，我接受聊天出题没有「请选科目/年级/题型」引导与规格回显——自由对话里直接说清楚即可（已明确的 UX 降级）。
5. 作为系统，我希望无任何路由模型时（decision 未安装 + llm 不可用）恒兜底可见集中 priority 最小者，路由永不返回 None。
6. 作为维护者，我希望 `AI_ROUTING_STRATEGY` 三值（llm / decision / auto）可切换，离线 CI 用 llm 策略可确定性跑。
7. 作为维护者，我希望动作直配（ADR-0081）不受本次移除影响，契约测试原样通过。
8. 作为维护者，我希望槽位存储从 `business:intent` 两本账回归单键，旧键行不读、无需迁移。
9. 作为维护者，我希望澄清路径（缺槽追问/DONE 补发/落库去回）仍被测试守护，即使聊天层暂不可达。
10. 作为部署方，我希望按规格结构化出题（`POST /tasks/generate`）完全不受影响。

## Implementation Decisions

- **兜底 = `min(visible, key=priority)`**：策略原语均不决策时取可见集中 priority 最小者（生产拓扑 tutor，priority=-10），`extra.routed_by="default"`；可见集按角色过滤，兜底随之受限。
- **`priority` 语义收缩**：不再参与「抢词」竞争（规则没了无处可抢），只剩「兜底助手 + manifest 清单呈现顺序」两个用途。
- **出题引导链连删不留壳**：`trigger` 是 `intent_schemas` 子意图分组的唯一选择器，删 trigger 则 `_business_triggered`/specs 注入/汇总帧/两本账全部失去存在理由；用户明确选择纯 LLM 生成。
- **`RouteDecision.trigger` 字段删除**：它是规则命中词的唯一出口；不留 deprecation 过渡（内部结构，无外部消费者）。
- **`intent_schemas` 删除**：tasks manifest 的 `input_schema` 保留为全 optional 声明（结构化端点与合成必填槽测试仍读它）。
- **`classify` 相关内核 helper 的存亡判据 = 是否被模型路由复用**：`_build_routing_state`/`_capability_text` 被 decision 与 llm 共用 → 留；纯规则辅助 → 删。

## Testing Decisions

- **文本路由的确定性来源 = 路由桩显式表态**：`FakeLLMProvider` 新增 `route_to` 旋钮（schema 为 `RoutingDecision` 时直接表态业务键）；新增 `RoutingFakeProvider`（预设 decision）。**不**在替身里嵌关键词猜测——那等于把规则匹配搬进测试替身。
- **新行为锁定**：`ROUTING_FALLBACK_REGRESSION`（8 句输入经 `decide` 全落 tutor/default，锁「规则确已移除、无模型恒兜底」）；真实配置组锁「聊天链路恒放行」：不澄清、不注入 specs、不发汇总帧、槽位按 business 单键落库、tutor 不冲掉 tasks、无关话不出题。
- **澄清路径守护**：`required_slots` monkeypatch fixture（`monkeypatch.setattr(svc, "_resolve_input_schema", ...)` 合成必填槽）在端到端层守护 5 测：缺槽澄清、DONE 补发回归（726dba9）、半成形只问剩余、落库 payload 同形、ADR-0100 一句话引导 + 回放气泡白名单。
- **回灌行为翻转**：`test_slot_context_carryover` 从「锁回灌」翻转为「锁不回流」——续话/换规格/长会话压缩/无关话均不注入 specs、无汇总帧；`merge_spec_layers`/`specs_from_context` 结构化语义 3 测保留。
- **删除的测试**：规则语义测试全家（路由回归表、词表契约、「出 N 道」族、词序不变量、`test_probe3.py` 无断言调试探针）。

## Out of Scope

- 不删槽位引擎（ADR-0095）：结构化端点仍依赖 `merge_spec_layers`/`specs_from_context`；通用澄清机制对将来声明必填槽的业务直接可用。
- 不改 agent 执行用通用 LLM（tutor/tasks 仍用教师 ModelConfig）。
- 不做 LLM 回传子意图（扩展 `RoutingDecision` 加 `intent` 字段的出题引导 2.0）——ADR-0104 §4 否决项，将来若要恢复引导 UX 时再评估。
- 不动 `POST /tasks/generate` 结构化端点与 `ctx.extra["specs"]` 端点侧链路。
- 不动前端（路由决策对前端不可见；manifest 无前端消费者）。
- 不实现长上下文压缩/摘要（除既有近期窗口裁剪）。

## Further Notes

- **验证**：`tests/ai` 353 passed；全量后端 1001 passed / 2 skipped / 1 failed——唯一失败 `tests/materials/test_empty_text_422` 为已知环境性红（与 main 基线一致：976 passed 时代同红）。
- **提交链**（分支 `ticket/08-decision-routing`）：`4fcc686`（T08 决策模型）→ `d8a9ed0`（可切换 LLM 分类）→ 本轮（rule 整体移除 + ADR-0104）。
- **ADR-0104 §3 已知项**：澄清路径的端到端覆盖率依赖合成 schema；`clarify_sentence` 话术由纯函数测试覆盖。726dba9 的「澄清轮补发 DONE」回归改由 `required_slots` 合成 schema 守护。
- **发布**：本地写本文件 + 更新 `INDEX.md`；GitHub 待 `gh auth login` 后执行
  `gh issue create --title "T09 — 移除规则路由（rule 决策整体下线，ADR-0104）" --body-file .scratch/ai-intent-routing/issues/09-remove-rule-routing.md --label ready-for-agent`

## 验收（由 User Stories 派生）

- [x] `router.py` 无 `classify`/`Classification`/`_rule_match`/启发式；`runtime.py` 策略只剩 decision/llm。
- [x] 三个 manifest 无 `triggers`/`hints`/`trigger_patterns`；tasks 无 `intent_schemas`。
- [x] `RouteDecision` 无 `trigger` 字段；`agent_core` 无 `classify` 导出。
- [x] `decide` 无任何模型时恒兜底（8 句实测输入全落 tutor/default）。
- [x] 端点测试 9 处经 `route_to` 旋钮显式声明落点后全绿（教师出题/查询/多跳/历史不吞工具/会话列表 kind/学生回放）。
- [x] 聊天链路恒放行：不澄清、不注入 specs、不发汇总帧；槽位按 business 单键落库。
- [x] `required_slots` 合成 schema 守护澄清路径 5 测（含 DONE 补发回归 726dba9）。
- [x] `test_slot_context_carryover` 翻转锁「不回流」；结构化语义 3 测保留。
- [x] `POST /tasks/generate` 端点测试不受影响（全量套件绿）。
- [x] `tests/ai` 353 passed；全量 1001 passed / 2 skipped / 1 环境性红。
- [x] ADR-0104 落 `docs/adr/`，关联 ADR-0098/0099/0100/0101/0081/0095 与提交 `4fcc686`/`d8a9ed0`。

## 纪律

- **不保留任何「不再被调用」的规则死层**：删就删干净（`router.py` 的 rule 分支、manifest 字段、`RouteDecision.trigger`、`intent_schemas` 全部物理删除），不留空壳。
- **兜底 = 可见集中 priority 最小者**，不引入任何关键词/启发式参与兜底决策。
- **动作直配（ADR-0081）永远在最前**，不受影响。
- **文本路由的确定性只能来自路由桩显式表态**（`route_to`/`RoutingFakeProvider`），禁止在测试替身里复刻关键词匹配。
- **主测试接缝仍是 `AgentRuntime.decide` 返回值**，不为路由逻辑新增内部接缝。
- 通用槽位机制（`fill_slots`/`clarify_sentence`/DONE 补发）保留但聊天层暂不可达——靠合成 schema 守护，不删机制。
