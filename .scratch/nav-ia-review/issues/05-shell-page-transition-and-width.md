# 05: 壳内页面的转场与宽度收口

**What to build:** 教师端在侧栏切页时有轻微的淡入转场，用户能感知「我换了地方」；同时页面不再一律被拉到同一个内容宽度——表单类与「我的」这类窄内容页用更窄的宽度，两侧不再大片留白。

**Blocked by:** 无（可立即开工）

**Status:** done

## 验收

- [x] 壳内切页有 ≤150ms 的淡入转场
- [x] reduce-motion 开启时转场时长为零（不靠缺省行为）
- [x] 每个页面可声明自己的内容宽度上限；未声明者沿用现有默认宽度
- [x] 表单类页面与「我的」用窄宽度居中，两侧不再大片空白
- [x] 转场不影响页面内的入场动画（既有列表逐条入场不得被叠加成两段动画）
- [x] push 出来的整页与壳内页的观感一致，不并存两套动画语言
- [x] widget 测试：切页触发转场；reduce-motion 下转场时长为零

## 落地笔记（commit 于 `ticket/nav-05` → `--no-ff` 合入 `integration/nav-ia-review`）

- 转场抽离到 `lib/shared/widgets/shell_body_transition.dart`：
  - 教师端（壳内 body 每次换页重建）用 `AnimatedSwitcher`（150ms 交叉淡入，`KeyedSubtree(key: ValueKey(pageKey))`；
    旧页淡出期间仍挂载 → 满足「淡入」且不影响 push 路由）。
  - 学生端（`IndexedStack` 常驻保活）用脉冲式 `_KeepAliveFade`（`AnimationController` 在 tabKey 变化时
    `forward(from:0)` 播 0→1，仅淡入、不换挂 → 满足「不影响页面内入场动画 / 不丢页签 State」）。
  - reduce-motion：`reducedMotionOf(context)` 显式归零（读 `MediaQuery.disableAnimations`，在
    `didChangeDependencies` 里同步 duration，避开 `initState` 读 MediaQuery 的非法调用）。
- 宽度收口：`AppContentFrame(maxWidth: AppLayout.contentNarrow)` 复用既有令牌；组合根 `HomeScreen`
  `_narrow(...)` 包裹表单类页（`CreateTaskPage`/`AddStudentPage`/`EditStudentPage`/`ProfilePage` 师生两端）。
  页面自身零改动，符合「不调整内部排版」纪律。
- 默认行为零变化：`AdaptiveShell.bodyKey` 默认 `null` → 6 个既有壳测试零影响。
- 测试：`test/nav_shell_transition_width_test.dart` 新增 7 例（教师切页转场 + reduce-motion 归零 +
  push 独立性 + 宽度声明 + 学生保活）。3 个既有 back/导航测试因 150ms 交叉淡入旧页挂载需补 `pump(200)`
  再断言旧页卸载（`teacher_back_stack_test`/`teacher_nav_single_source_test`/`ai_run_trace_page_test`）。

## 纪律

- 转场只作用于**壳内换页**，不得影响 push 路由的既有转场。
- 宽度仍走既有布局令牌，不得写裸数字；窄宽度只是给页面一个可声明的出口，不是新增一档断点。
- 本票不调整任何页面的内容排版。
