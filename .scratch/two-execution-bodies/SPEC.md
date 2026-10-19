# 二执行体拓扑 · SPEC

> ADR：`docs/adr/0098-two-execution-bodies.md`（权威决策）。
> 分支：`integration/two-execution-bodies`（自 main 拉出，worktree `/tmp/oedu-2eb`）。

## 目标

执行体收敛为 2 个：tutor（独立引擎）+ tasks（吸收 question 与 students）。
capability 保留零 LLM 实现，定位为路由层固定回复，不计执行体。
question / students 两个 business 键消失，功能全部归置到 tasks。

## 非目标

- 不改 tutor 的任何行为（安全闸门 / RAG / persona / 流式）。
- 不动 07 票（前端草稿确认卡 task_draft_card 渲染 + confirm/assign REST 端点）——那属
  business-feature-agents epic 的遗留，与本拓扑变更正交。
- 不删 capability 的 subagent 形态（ADR-0098 §3 被否方案第 4 条）。

## 目标形态

```
路由层：capability（零 LLM，清单从 manifests 生成）
执行体：tasks（12 工具，tool loop，requires_tool_data=True）
执行体：tutor（TutorService，零工具）
```

tasks/ 目录终态：

```
tasks/
  agent.py          合并后的 tool loop agent（12 工具）
  manifest.py       triggers 并集 + task_generate + question_sop + intent_schemas
  skills/question_sop.md   出题纪律（自 question/ 迁入）
  tools/            12 个工具（学情 7 + 名单 1 + 草稿 1 + 出题 1 + 题库 3）
  generation/       specs / pipeline / translate / parsers（自 question/ 迁入）
```

## 机制变更：slot filling 按意图分组

manifest 新增 `intent_schemas`（触发词子集 + schema）；路由器 `_rule_match` 返回命中词；
`RouteDecision` 增 `trigger`；service 预检按 intent 选 schema、槽位键
`business` / `business:intent` 两本账；specs 注入条件 `intent == "generate"`。

## 验收

1. 全量 pytest 与基线等价：976 passed + materials 环境性红（main 既有），零新增红。
2. discover 装配恰 3 个 manifest；capability 清单双端内容正确（tasks 双域描述）。
3. 路由关键句实测：出题句 / 学情句 / 名单句 / 元问题句 / 超范围句各归其位。
4. 多轮出题澄清（缺 grade → 只问 qtype → 出题）与「已确认规格」汇总帧行为不变。
5. `POST /tasks/generate` 多学科出题与部分失败短报行为不变。
