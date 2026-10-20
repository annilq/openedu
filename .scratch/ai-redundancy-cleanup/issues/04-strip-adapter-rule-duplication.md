# T04 — 路由适配器去重：剥离 `classify_llm` 提示词里硬编码的已删规则（候选 3）

**What to build:** 路由当前有两套并行适配器——`LayaDecisionModel`（`agent_core/adapters/laya.py`，仅 `laya-multilingual`）与 `classify_llm`（`agent_core/adapters/llm_route.py`），靠 `AI_ROUTING_STRATEGY` 策略开关二选一，prod 实际只跑其一。问题不在「有两套可选」，而在 `llm_route.py:37-45` 的 `ROUTING_SYSTEM_PROMPT` **硬编码了 3 条编号路由规则**（「进行中任务改参数沿用上一轮助手」「学生作答路由伴学答疑」「只输出业务键原文」），这与 ADR-0104「规则整体移除、不根据规则分类路由」正面冲突——规则被偷偷写回了 LLM 提示词。本票把规则文本从提示词里剥离，路由完全交给能力清单 + 近期上下文，使两套适配器的语义一致、且都符合 ADR-0104。

**Blocked by:** 无
**Status:** ready-for-agent

## 决策锚点

- **去重 ≠ 删掉 LLM 分类器**：保留 `classify_llm` 作为策略可选项，但提示词只描述「按能力清单 + 上下文选业务键」，不再内嵌任何 if/elif 式规则。
- 剥离后必须跑路由回归：决策模型与 LLM 分类两种策略下，`ai-intent-routing` 的实测底稿（7 行路由表）结论不得翻转。
- 若实测发现「去掉规则后 LLM 分类在连续性/学生作答两类上退化」，那是路由质量议题，回到 `ai-intent-routing` 的弱意图兜底 backlog，**不要**把规则悄悄加回提示词。
- 适配器文件本身（laya.py / llm_route.py）保留；本票只动提示词文本 + 必要的 schema 注释。

## 验收

- [ ] `agent_core/adapters/llm_route.py` 的 `ROUTING_SYSTEM_PROMPT` 不再含「沿用上一轮」「学生作答路由伴学答疑」等硬编码规则（只保留能力清单 + 上下文 + 输出业务键的格式约束）
- [ ] 新增/复用「提示词快照」断言：classify_llm 提示词不含编号规则
- [ ] `AI_ROUTING_STRATEGY` 两种取值（`decision` / `llm`）下，路由用例（`tests/ai/test_decision_model_routing.py`、`test_laya_adapter.py` 及既有 classify 用例）全绿，且与 `ai-intent-routing` 实测路由表一致
- [ ] `docs/adr/0104` 结论（规则已移除）与本票实现一致；如有偏差在票内记录
- [ ] `ruff` 改动文件净
