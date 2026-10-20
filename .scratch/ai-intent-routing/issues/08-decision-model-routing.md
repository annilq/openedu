# 08: 决策模型路由替代规则分类（Laya-multilingual）

> 标签：`ready-for-agent`
> 来源对话：2026-10-20 路由缺陷复盘 + 决策模型评估（trace `2319bc50`、`73000ee0`）
> 关联：ai-intent-routing Backlog 首条「接上**真的被调用**的弱意图 LLM 兜底」；`router.py` 文档预留的「LLM 兜底扩展点」；ADR-0081（动作直配）/ ADR-0098（意图信号）/ ADR-0101（触发词正则）

**What to build:** 把当前的「规则分类路由」（字面子串 + 正则 + 启发式兜底，每条消息独立无状态）替换为**混合路由**：动作直配（ADR-0081，不变）→ 决策模型（`predict(state=近期 history+当前消息, options=可见 business)`）→ 低置信/不可用时回落规则 `classify` → 兜底最低优先级业务。决策模型采用 `convaiinnovations/laya-multilingual`（非自回归 System 1 决策模型：encoder + 决策头，单次前向返回校准概率，本地 ~40ms，Apache-2.0，中文可用），按其原生「state + 类型化选项 → 校准概率」接口实现「每轮带全量上下文、按 agent 能力路由」，一次性根除「出一道」首轮 miss 与「数学」续接落 tutor 两个已确认 bug。

**Blocked by:** —（建在已落地的 01–07 路由归一之上；不依赖任何未合入分支）

**Status:** `ready-for-agent`（本地草稿；GitHub 未登录，待 `gh auth login` 后建 issue 打此标签）

## Problem Statement

用户视角：在 AI 对话里，本应返回场景化出题的意图，却经常拿到一段纯文本讲解。复盘两条真实运行轨迹，根因是**路由是「每条消息独立、无会话上下文」的规则分类**：

- 首轮「请为「图形的运动（轴对称）」出一道选择题」：规则层靠字面子串命中，`tasks` 的触发词是 `出道`，而「出一道」子串不连续 → 全 miss → 落到兜底最低优先级业务 `tutor` → `tutor_explain` 只产文本（trace `2319bc50`）。
- 续接「数学」（疑似改年级的短消息）：首轮已正确出题，但后续短消息被当全新消息独立分类、无任何出题触发词 → 又落 `tutor` → 纯文本（trace `73000ee0`）。

两个 bug 的共同根因是**同一个**：路由不感知会话上下文、也不理解语义，只能靠脆弱的词表/正则。之前提出的「加黏性业务分支」方案被否决——它只是在拐点继续堆分支，不优雅。

## Solution

用**决策模型**替代规则分类作为主路由原语，并保留规则层作确定性兜底：

1. **动作直配优先**（ADR-0081，不变）：结构化 `action` 等值匹配，仍排在文本路由之前。
2. **决策模型主路由**：把最近对话 history（裁剪到模型上下文窗口）+ 当前消息作为 `state`，把当前角色可见的 business 列表（每个带 `name`/`description`/`actions` 作为选项 criteria）作为类型化 `choice` 问题，调 Laya 返回「选哪个业务 + 校准概率」。
3. **阈值门控 + 规则兜底**：概率 ≥ 阈值 → 路由该业务；否则回落 `router.py` 的规则 `classify`；再不行 → 兜底最低优先级业务。
4. **模型不可用兜底**：决策模型未安装/离线/超时时，静默走规则 `classify` → 兜底，链路不崩。

这天然实现用户要的两点——「每轮保持所有消息上下文」（history 进 state）与「按 agent 能力路由」（manifest 的 `description`/`actions` 即能力清单），且**不产生黏性业务分支**：续接「数学」由模型读上下文判断为「补参数→留出题」，作答「选B」由模型判断为「交 tutor」，无需手写分支。

## User Stories

1. 作为教师，我希望「出一道四年级数学选择题」这类首轮出题请求被正确路由到出题助手，以便拿到场景化题卡而不是一段文本讲解（不再因「出一道」子串不连续而 miss）。
2. 作为教师，我希望出题后的后续短消息（改年级、「三年级」「换成一年级」、补科目）留在出题会话里重出场景化题卡，而不是掉进伴学答疑返回纯文本。
3. 作为学生，我希望在出题会话里发的作答信号（「选B」「对」「我不会」）被正确路由到伴学答疑/tutor 判定，而不是卡在出题体里。
4. 作为用户，我希望任意一轮的路由都基于完整对话上下文，而不是只看孤立的当前句。
5. 作为路由系统，我希望按 agent 能力（manifest 的 `description`/`actions`）选择业务，新增 subagent 时自动扩展候选集，无需改路由代码。
6. 作为维护者，我希望决策模型返回校准置信度，低置信时回落规则 `classify`，不会因模型误判而答非所问。
7. 作为系统，我希望决策模型不可用时（未安装/离线/超时）静默回落规则 `classify` → 兜底最低优先级业务，链路不崩。
8. 作为用户，我希望中文输入下路由准确（使用 `laya-multilingual`，而非英文 `laya`）。
9. 作为部署方，我希望决策模型本地自托管（CPU/GPU），零按调用成本、数据不出域，契合儿童教育产品合规要求。
10. 作为教师，我希望「换一题」「再出几道」这类延续性请求在上下文里被正确识别为出题延续。
11. 作为学生，我希望混合意图（先出题、后追问知识点讲解）在上下文里逐轮正确分流。
12. 作为维护者，我希望路由决策可观测：`conversation.kind` 记录本轮业务，运行轨迹可复盘决策路径与走了哪条分支。
13. 作为维护者，我希望路由回归测试不依赖网络或模型权重（用内存桩），CI 稳定。
14. 作为维护者，我希望真实 Laya 适配器有独立冒烟测试，缺失权重时跳过而非红，不阻断 CI。
15. 作为用户，我希望路由延迟不可感（决策模型 ~40ms 本地前向，与「正在选择助手」思考帧并发发出）。
16. 作为维护者，我希望动作直配（ADR-0081 结构化 `action`）仍优先于决策模型，完全不受影响。
17. 作为维护者，我希望触发词正则（ADR-0101）作为确定性快路径/覆盖保留，但不再是主路由；规则 `classify` 作为兜底保留。
18. 作为教师，我希望当知识点关联了场景模板时，路由修好后的出题返回带 `scene_spec` 的场景化题卡（由现有 `_attach_scene_spec` 产出）。
19. 作为维护者，我希望置信度阈值可配置，默认值经实测标定（考虑 base checkpoint 过自信）。
20. 作为用户，我希望长对话下 history 被裁剪到模型上下文窗口（近期 N 轮或滚动摘要），不超出 token 预算。

## Implementation Decisions

- **新增唯一模块：`agent_core/adapters/` 下决策模型端口**（与 `genkit.py` 平级）：`DecisionModel` 抽象 + `LayaDecisionModel` 实现。接口 `predict(state, questions) -> list[Answer]`，路由特化为 `route(history, candidates) -> (business, prob)`，返回校准概率。
- **`runtime.py` 的 `decide` 增加 `history`/`session` 形参**；`service.py` 把已读出的 `conversation`/`history` 传入。动作直配（`runtime.py` 现有路径）仍排在最前（ADR-0081，不变）。
- **路由链顺序固定**：动作直配 → `DecisionModel.predict`（state=近期 history+当前消息；options=可见 business 的 `name`/`description`/`actions`）→ `prob ≥ 阈值 ? 路由（extra 标 `level="decision"`） : 规则 classify（router.py）` → 兜底最低优先级业务。
- **能力清单元数据来自已发现的 `SubAgentManifest`**（`description`/`actions`），无新真源；加 subagent 自动扩展候选。
- **决策结果以 `level="decision"` 记入 `RouteDecision.extra`**，保留 `level` 字段供测试断言走了哪条路径（延续既有 `rule`/`heuristic`/`fallback` 的判定契约）。
- **置信度阈值可配置**（默认经实测标定）；低于阈值或模型不可用 → 回落规则 `classify` + 兜底。
- **`conversation.kind` 继续记录决策业务**（现有可观测性不变）。
- **保留 `router.py` 的规则 `classify`** 作为确定性兜底 + 离线测试用；ADR-0101 触发词正则可保留为可选确定性快路径，但不再担当主路由。

## Testing Decisions

- **主接缝 = `AgentRuntime.decide` 返回值**（复用 ai-intent-routing 既有测试缝）：断言 `(signal + role + history) → RouteDecision`，**不**碰内部级别、不断言匹配第几个词；新增 `level="decision"` 用于区分走了决策模型还是规则兜底。
- **`DecisionModel` 端口：契约测试用内存桩**（返回预设 choice/prob）；路由集成测试全部走桩，无网络/权重依赖。
- **真实 Laya 适配器：独立冒烟测试**，缺权重/离线时跳过（沿用现有 env-dependent red 约定，如 `materials test_empty_text_422`）。
- **Golden eval 集**：两条真实 trace（`2319bc50`、`73000ee0`）+ 代表性输入（出一道 / 数学续接 / 选B作答 / 换一题 / 查为什么选B / 今天有什么作业 / 给我讲讲这个知识点）。回归断言：出题会话发「三年级」仍 `tasks`、发「选B」仍 `tutor`、模型不可用→规则兜底、误用非 multilingual 的 `laya`→配置/测试显式拒绝或强制 multilingual。
- **必须补真实 `classify` 路径**：此前 `test_slot_filling_integration` 用 `_StubRuntime` 把 business 钉死成 `tasks`，掩盖了续接路由缺口；本票须用 `DecisionModel` 桩覆盖真实路由分支。

## Out of Scope

- 不替换 agent 执行用通用 LLM（`tutor`/`tasks` 仍用教师 ModelConfig 的通用模型）。
- 不微调/重训 Laya。
- 不改 slot-filling / `intent_schemas`（ADR-0098）逻辑。
- 不做长上下文压缩/摘要（除简单近期窗口裁剪）。
- 不彻底删除规则 `classify`（保留兜底 + 离线测试）。
- 不实现此前被否决的「黏性业务分支」方案。

## Further Notes

- **Laya-multilingual**：mmBERT-base 322M、1024 tok（可扩 8192）、100+ 语言含中文、Apache-2.0、本地自托管、~40ms/问题（Tesla T4）。它是**非自回归决策模型，不生成文本**，接口即 `predict(state, questions)`。
- **硬前提①**：必须用 `laya-multilingual`，**绝不能用英文 `laya`**（英文版在非英语上「自信但错误」，高棉语 0.000 准确率仍高置信，仅 23/51 语种过 3×随机）。产品是中文。
- **硬前提②**：决策模型走新 `DecisionModel` 端口，**不进 `LLMProvider`(genkit) 聊天抽象**（它是分类器不是聊天模型）。Agent 执行仍用通用 LLM，不冲突。
- **校准**：base checkpoint 过自信（出厂 ECE 0.466，按类型温度校准后 0.081）→ 阈值 + 规则兜底缓解；小 N 选择（2–4 业务）是 Laya 强项，大标签集（77+）弱项——本场景安全。
- 本票实现 ai-intent-routing Backlog 首条「接上真的被调用的弱意图 LLM 兜底」，并兑现 `router.py` 文档预留的「LLM 兜底扩展点」。
- **发布**：本地写本文件 + 更新 `INDEX.md`；GitHub 待 `gh auth login` 后执行
  `gh issue create --title "T08 — 决策模型路由替代规则分类（Laya-multilingual）" --body-file .scratch/ai-intent-routing/issues/08-decision-model-routing.md --label ready-for-agent`

## 验收（由 User Stories 派生）

- [ ] 首轮「出一道四年级数学选择题」路由到出题助手（不再是伴学答疑）。
- [ ] 出题会话后续发「数学」/「三年级」/「换成一年级」仍路由 `tasks` 并重出场景化题卡。
- [ ] 出题会话发「选B」/「我不会」路由到 `tutor`（不卡在出题体）。
- [ ] `decide` 接收到 `history` 且决策模型以其为 `state`（全量上下文进入路由）。
- [ ] 决策模型返回校准概率；低于阈值时回落规则 `classify`。
- [ ] 决策模型不可用（未安装/离线/超时）时静默走规则 `classify` → 兜底，链路不崩。
- [ ] 配置/测试显式守护：仅 `laya-multilingual` 可用，拒绝英文 `laya`。
- [ ] 主测试接缝为 `decide` 返回值；`DecisionModel` 端口有内存桩契约测试；真实 Laya 适配器冒烟测试可离线跳过。
- [ ] Golden eval 集（两条真实 trace + 代表性输入）作为回归，断言续接与作答分流正确。
- [ ] 动作直配（ADR-0081）仍在决策模型之前且不受影响。
- [ ] 路由延迟不可感（与「正在选择助手」思考帧并发）。

## 纪律

- 必须用 `laya-multilingual`，**禁止英文 `laya`**（配置与测试显式守护）。
- 决策模型走新 `DecisionModel` 端口，不进 `LLMProvider`(genkit) 聊天抽象。
- 动作直配（ADR-0081）永远在决策模型之前，不受影响。
- 规则 `classify` 保留为兜底 + 离线测试，不删。
- **主测试接缝 = `decide` 返回值**，不为路由逻辑新增内部接缝。
- 尊重 ADR-0098 / ADR-0081 / ADR-0101；不重排触发词优先级，不拍平「课件出题 vs 助手出题」双语义。
- 路由延迟不可感：与思考帧并发，不阻塞首字。
