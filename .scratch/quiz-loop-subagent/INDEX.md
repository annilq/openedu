# 判断题闭环子代理化：后续工单（ADR-0090）

> 来源 ADR：`docs/adr/0090-quiz-loop-subagent-answer-in-history.md`；实施 spec：`docs/adr/0090-spec.md`
> 背景：主重构已落地（提交 `2c37fa0` 后端 / `e035757` 测试 / `fce6b07` 前端 / `aeeaf51` ADR / `c2d98c2` spec）。
> 本组工单收尾两件事：① spec 测试决策明记的**必补缺口**——判断题卡组件零覆盖；
> ② 核验本轮改动时发现的**三个前端既存红**（当前 HEAD `c2d98c2` 干净 worktree 复现确认，非本轮引入）。

## Tickets（依赖序，blockers first）

| ID | 标题 | Blocked by | Status |
|----|------|-----------|--------|
| 01 | 补判断题卡揭示行为的组件测试 | — | done |
| 02 | 修 students → home 横向 import 违反 R2 | — | done |
| 03 | 清理 stretch_row_guard 过期基线条目 | — | done |
| 04 | 修 students_notifier 空字段校验测试的挂起计时器 | — | done |

## 决策锚点（写进每张 ticket）

- **四票互不依赖**，全在 frontier，可并行；顺序仅为了可读性。
- **02 / 04 不合并**：同属 students 区域但病灶不同（分层 import 违反 vs 测试装置计时器），合并会让一张票跨两类排查上下文。
- **03 是基线过期不是新违规**：失败方向是「站点已消失或已修复，请从基线删除」；删条目 = 承认已修（棘轮只许下调，ADR-0044），不是放松守卫。
- **token 成本不开票**：历史题卡文本使 `_read_history` 变长一事，经确认仅记录在 spec Further Notes，不开优化工单。
- **揭示态不持久化不开票**：spec Out of Scope，01 只测内存态契约。

## 最容易回归的断言（实施时不可省）

- **01**：无 Material 祖先树下真构建；未揭示三样文本（答案 / 解析 / 出题思路）均不在场；禁 `toImage` 截图装置。
- **02**：R2 守卫绿；下沉 shared 的能力不得反向依赖 features；学生管理既有测试 0 回归。
- **03**：删条目前全仓确认站点确已消失；不新增裸 `Row(stretch)`；其它过期条目一并清理并注明原因。
- **04**：连跑 3 次稳定；改测试装置不改产品校验逻辑；修后全量既存红 3 → 2（不越界修 02 / 03 的账）。

## 测试缝

- **主缝（前端组件）**：`AssistantQuestionCard` widget 测试，无 Material 祖先树真构建——先例 `assistant_sources_bar_test.dart`（01）。
- **守卫缝**：`feature_boundaries_test.dart` R2 / `stretch_row_guard_test.dart`——修后在干净 worktree 复跑确认归零（02 / 03）。
- **装置缝**：`students_notifier_test.dart` 按五坑纪律处理 pending timers（pumpAndSettle 陷阱、平台覆写复位）（04）。
- **后端不设缝**：本组四票全在前端 / 测试层，后端 ADR-0090 主缝（聊天 SSE 端点）已由 `test_quiz_loop.py` / `test_assistant_quiz.py` 守着，无需新缝。

## 转 GitHub issue 步骤（待登录）

1. `gh auth login`（当前未登录；`gh auth status` 确认）
2. 按编号顺序逐张建 issue（本组无边，顺序仅为了可读性）
3. 全部打 `ready-for-agent` 标签
4. 建完把各 issue 编号回填到上表 Status 列旁的备注

## Backlog（延后待办，不在本组 4 票内）

- 历史题卡文本的 token 成本优化（如只对 tutor 路由轮渲染题卡文本）——spec Further Notes 记录在案，经确认不开票
- 判断题卡揭示态跨刷新 / 跨端持久化——spec Out of Scope
- `pending_quiz` 列存量未判定题补偿——随列消失视为会话结束，spec 明记不补偿
