# 03: 同规格出题合并为一次请求（array schema）

> 标签：`done`（2026-10-21，ADR-0108）
> 来源对话：2026-10-21 用户「按照 4 个提案优化」提案 3
> 关联：ADR-0023（唯一安全闸门）、ADR-0032（契约与解析器同源）、ADR-0097（出题 = 流式 tool）、
> ADR-0098（question 域并入 tasks）

**落地摘要**：`QuestionListSchema`（元素是同一个 `QuestionSchema`）+ `assemble_questions`
逐元素过同一道闸门；调用方按「不可变身份」分组，一组一次请求。3 道 = 1 次请求（此前 3 次）。
**代价显式接受**：题卡不再逐题流出（约束解码的 JSON 只在末帧整块到达）。
**收益**：本地小模型逐题串行出 2 道实测 19–36 秒（提交 `77f69134` 为此把 SSE 超时抬到 10 分钟）。

## Problem Statement

1. 出题是逐题串行：一道 = 一次 `stream(schema=QuestionSchema)`，N 道 = N 次完整往返。
2. 逐题串行换来两样东西，本票把它们**分开处理**：逐题流式（用户边等边看第 1 题）与
   逐题闸门（一道不过闸只丢那一道，不连坐）。请求可以合并，闸门不能合并。

## Solution

1. `QuestionListSchema` 与 `assemble_questions` 同文件（契约与解析器同源，ADR-0032 延伸到批量）。
2. 调用方 `_group_items` 按 `_identity`（subject/grade/knowledge_point/qtype/difficulty/semester/
   multi/judge）分组，一组一次 `stream_questions`；`count == 1` 仍走单题路径。
3. 短差留痕：`cards < count` 时补 `STEP(status="error")`「少出 M 道」并记进 `failures`
   （整批失败时用 `fatal` 标志避免一道题算两笔）。
4. 批量 prompt 额外要求逐题异构（「这 N 道题必须彼此不同…否则等于只出了一道题」）——否则
   模型会把同一道题换个数字重出 N 遍，那比逐题串行还糟。

## Implementation Decisions

- **元素不携带身份字段**：那些是 `QuestionSpec` 的不可变身份，由调用方回填。让模型改写身份
  等于把规格决定权交出去；混装任意规格不是「顺便支持」，而是开一个口子。
- **不静默补位**：`assemble_questions` 只丢不补（拿一道不过闸的题冒充好题比少一道更糟）。
- **替身必须跟 `output_schema` 走**：`tests/utils/fake_provider.py` 在 `QuestionListSchema` 下
  按 prompt 说的「出 N 道」给数组。否则「契约与解析器漂移」被替身完美掩盖——表现为
  「要 6 道只出 1 道，且无报错」，这是本票落地时**实际撞到**的形态。

## 验证

- `tests/ai` 新增 6 条批量用例 + 1 条逐题闸门（不连坐）用例，全量 `tests/ai` **424 passed**。
- 端点级：`tests/api/routes/test_tasks_generate.py` 单行 count=2 出 2 张、2+1+3 出 6 张。
  （落地时这两条先红，正是替身没跟 schema 走暴露的。）
- 全量后端 **1078 passed / 2 skipped / 1 环境性红**（`materials test_empty_text_422`，与基线一致）。
