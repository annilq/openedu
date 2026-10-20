# AI 意图路由归一：所有服务走同一个裁决点

> 来源 spec：`docs/specs/ai-intent-routing-unification.md`（GitHub issue 正文源）
> 设计底稿：`docs/refactor/2026-10-10-ai-intent-routing-unification.md`（带实测行号与分批清单）
> 决策记录：`docs/adr/0081 §2.3`（已由本次反转：动作类**仍走** `rt.decide`）
> 术语以 `CONTEXT.md` 为准。范围 P0 + P1 + P2，一次写全。

一句话：**路由的输入从「一段文本」升级为「结构化意图信号」，路由仍是唯一裁决点。**
动作走的是一类不参与文本竞争的匹配（等值匹配、声明在 SubAgent 清单里），
所以既不会误判，也不会有「谁的优先级更高」的军备竞赛。

## Tickets（依赖序，blockers first）

| ID | 标题 | Blocked by | Status |
|----|------|-----------|--------|
| 01 | 删除从未生效的 LLM 分类器参数（prefactor） | — | done |
| 02 | 意图信号与动作直配内核 | 01 | done |
| 03 | 修掉单字触发词「查」的误判 | — | done |
| 04 | 按规格出题走统一路由 | 02 | done（动作直配内核 + 端点接线已落地；「服务端按动作合成落库消息」随 ADR-0081 删除结构化端点一并做，见 Backlog） |
| 05 | 换一题走统一路由 | 04 | done |
| 06 | 课件上下文与待判定态定向迁进信号 | 04 | done |
| 07 | 判断题闭环走运行时（含前端帧兼容） | 06 | done |
| 08 | 决策模型路由替代规则分类（Laya-multilingual） | — | done（实现于分支 `ticket/08-decision-routing`） |
| 09 | 移除规则路由（rule 决策整体下线，ADR-0104） | 08 | done（实现于分支 `ticket/08-decision-routing`；推翻 08「规则 classify 保留兜底」的纪律） |
| 10 | 无命中兜底改为能力引导（tutor 显式化，ADR-0105） | 09 | done（实现于分支 `ticket/08-decision-routing`；取代 ADR-0104 §2.1 兜底子句） |

**全部 ticket 已落地（含 08、09、10）。** 08 在分支 `ticket/08-decision-routing` 实现并自测通过：新增 `DecisionModel` 端口（`agent_core/ports.py`）+ `LayaDecisionModel` 适配器（仅 `laya-multilingual`，英文 `laya` 显式拒绝；`available()` 无权重/无 `LAYA_SERVE_URL` 时为 False）+ `runtime.decide` 透传 `history` 并接入决策模型作主路由、规则 `classify` 当时退为兜底 + `service.py` 路由前算 `prior_history` 并注入 `get_decision_model()`；随后 `d8a9ed0` 新增可切换的通用 LLM 结构化分类 `classify_llm` 与 `AI_ROUTING_STRATEGY` 开关。新增 `tests/ai/test_decision_model_routing.py` / `test_laya_adapter.py`（内存桩，无权重/网络依赖）。

**09 在 08 之上把规则层整体移除**（ADR-0104，用户定调「不根据规则分类路由，直接使用 llm 分类，每轮保持所有消息上下文，按 agent 能力路由」）：`router.py` 删 `classify`/`_rule_match`/启发式，`runtime.py` 策略收敛为 `llm=[llm]`/`decision=[decision,llm]`/`auto=[decision,llm]`（默认）、均不可用 → 兜底可见集中 `priority` 最小者（生产拓扑 tutor，`routed_by="default"`）；manifest 删 `triggers`/`hints`/`trigger_patterns`（tasks 的 `intent_schemas` 一并删），`RouteDecision` 删 `trigger`；出题引导链（`_business_triggered` 闸门、specs 聊天侧注入、「已确认规格」汇总帧、`business:intent` 两本账）随 `trigger` 消失一并移除，聊天出题改纯 LLM 自由文本生成（AskUserQuestion 确认的 UX 降级）。保留：动作直配（ADR-0081）、通用槽位引擎（`fill_slots`/`clarify_sentence`/DONE 补发，由合成必填槽守护）、`POST /tasks/generate` 结构化端点。验证：`tests/ai` 353 passed；全量后端 1001 passed / 2 skipped / 1 failed（`materials test_empty_text_422` 已知环境性红，与 main 基线一致）。

**10 在 09 之上收窄兜底语义**（ADR-0105，用户定调「tutor 也需要显式触发，不作为兜底逻辑，都没有命中则提示自身能力引导」）：`SubAgentManifest` 新增声明式字段 `fallback_guide`，capability 声明之——都没有命中（决策模型 / LLM 分类均不决策）时由它给出「职责边界 + 你可以让我：…」的零 LLM 固定引导；**所有执行体（tasks / tutor）必须被模型显式路由到**，不再有执行体充当隐式兜底；priority 语义纯化为「清单呈现顺序」，`min(priority)` 降级为「无声明时的最后防线」（当前拓扑不可达）。契约测试守护「至多一个声明 + 双端可见」；兜底回归表（8 句）翻转为断言 capability；学生伴学用例显式 `route_to="tutor"` 后才落 TutorLog。验证：`tests/ai` 355 passed；全量 1003 passed / 2 skipped / 1 环境性红；ruff 改动文件全净。
**Frontier：空。**

> 并行执行分析：T05 ‖ T06 文件集不相交（T05=`features/tasks/*`，T06=`features/assistant/*`+清单），可并行；T07 与 T06 改同一段对话编排，**必须串行**（票据已注明）。实际执行即按此：T05/T06 并行于两个 worktree，T07 待 T06 合并后开工。

## 决策锚点（写进每张 ticket）

- **动作直配 = 等值匹配 + 排在触发词之前 + 不参与优先级排序**。唯一性由契约测试保证，故无需排序规则。
- **动作不可见必须显式**（端点转 403），不许沿用「换成第一个可见业务」的静默兜底——那会把越权变成答非所问。
- **未知动作回落自然语言路由且不报错**。代价是动作名与清单不同步会静默失效 → 契约测试是硬要求。
- **归属校验 ≠ 角色可见性**：换一题的「任务不存在」是归属校验（资源不存在与越权不可区分），
  与动作不可见的角色语义是两回事，不得混用。
- ~~**不重排任何触发词优先级**：现有优先级是实测调出来的，重排会推翻 ADR-0054 的结论。~~ **已被 ADR-0104 废止**：触发词（`triggers`/`trigger_patterns`）随规则路由整体移除，本条只对 01–07 的历史有效。
- **两种「出题」语义不得拍平**：课件里 → 任务引导（引导到页面）；助手里 → 出题助手（真出卡）。
- **两类剥离得分清**：流程性剥离（判断题题面去答案，先出题后揭示，教师端同样剥）**保留**；
  角色性裁剪（按角色投影）已按 ADR-0081 §2.8 反转为一律全量下发、客户端控显。

## 实测底稿（实施时不可省，别重新猜）

用真实 manifest 实跑路由分类（2026-10-10）：

| 输入 | 结果 | 期望 |
|---|---|---|
| `""`（结构化出题现在传的就是空串） | 伴学答疑 ❌ | 出题助手 |
| `出 3 道四年级下学期数学题，知识点：轴对称` | 伴学答疑 ❌ | 出题助手 |
| `换一题` | 伴学答疑 ❌ | 出题助手 |
| `查一下这道题为什么选B` | 学情查询 ❌ | 伴学答疑 |
| `帮我出2道四年级数学题` | 出题助手 ✅ | 出题助手 |
| `今天有什么作业` | 学情查询 ✅ | 学情查询 |
| `帮我创建一个任务，包含四年级数学题` | 任务引导 ✅ | 任务引导 |

**这就是「让路由去猜结构化请求」行不通的实证**：出题助手的触发词是「出题 / 出几道 / 题目 / 来几道」，
一个都匹配不上「出 3 道…题」，启发式也落空，最后掉到兜底的最低优先级业务。

## 测试缝

- **只有一个接缝：`AgentRuntime.decide`**。所有断言打在它的返回值上（动作直配、不可见、
  未知动作回落、安全闸门是否被调用）。沿用既有路由用例的形状，不新增接缝，端点与数据库层不测。
- **好测试的判据**：只断言「给定信号 + 角色 → 路由决策是什么」，**不断言内部走了哪一级、匹配第几个词**，
  这样三级路由以后怎么重排测试都不碎。
- 契约测试：动作归属唯一性（无孤儿 / 无悬空）、不受清单遍历顺序影响、不可见不回落。

## 转 GitHub issue 步骤（待登录）

1. `gh auth login`（或设 `GH_TOKEN`）
2. 按编号 01→07 顺序建 issue（blockers first），`Blocked by` 指向 blocking issue 编号
3. 全部打 `ready-for-agent` 标签

建 issue 命令模板：
`gh issue create --title "T0N — <标题>" --body-file .scratch/ai-intent-routing/issues/0N-<slug>.md --label ready-for-agent`

## Backlog（延后待办，不在本轮 7 票内）

- 接上**真的被调用**的弱意图 LLM 兜底 → **已由 ticket 08 承接并实现**（采用 `convaiinnovations/laya-multilingual` 决策模型：非自回归、本地 ~40ms、中文可用、校准置信度门控；当时规则 `classify` 退为兜底 + 离线测试，**该规则兜底已由 ticket 09 / ADR-0104 整体移除**）。原「只删掉那个从未生效的参数」为 01 已完成的 prefactor 部分。
- 删除结构化出题端点与两个同步重生成端点（属 ADR-0081 的落地，非路由归一）
- ADR-0082 的题目归属与学生题库（本轮只要求「不阻断」，落点由它负责）
- 学生题库视图「默认只显示练过的」（ADR-0082，防生成日志淹没）
- 掌握度漏统计缺陷（未落库题把任务题 id 当题目 id 写进作答记录）——独立议题
