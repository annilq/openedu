# 09: 导航可见性：侧栏徽标与紧凑档当前页标题

**What to build:** 待审核草稿数这类需要拉取注意的信号在侧栏「任务」项上可见——离开概览页也看得到；紧凑档顶栏显示**当前页面名**，教师收起抽屉后仍然知道自己在哪，而不是永远看到同一个应用名。

**Blocked by:** 01（标题映射表）、07（改名与分组后的菜单结构）

**Status:** ready-for-agent

## 验收

- [x] 侧栏「任务」项在有待审核草稿时显示数量徽标，为 0 时不显示
- [x] 徽标与既有的出题进度徽标不打架：同一槽位有明确优先级，或显式分成两个语义
- [x] 紧凑档顶栏显示当前页面名，取代固定的应用名
- [x] 下钻页显示的是**下钻页自己**的名字，不是父级名字
- [x] 标题过长时省略而非溢出
- [x] 徽标走既有徽章组件与色彩语义，不新增第四种强调色
- [x] widget 测试：徽标随数量出现/消失；紧凑档标题跟随切页（含下钻页）

## 落地记录（2026-10-14，分支 ticket/nav-09 → integration/nav-ia-review）

- 草稿计数派生自 `teacherTasksNotifierProvider`（draft+ready = 「草稿箱」Tab 总量，
  服务端随每次 `GET /tasks` 响应下发全量计数，离开任务页后跨页常驻），新增
  `teacherDraftCountProvider`；为 0 不显示徽标。
- 「任务」项尾部 `_taskTrailing`：**显式分槽**——草稿徽标走既有 `AppBadge`（outlined/
  surfaceSunken 语义，无第四种强调色）占一格，出题进度徽标（accent 实色瞬态）占另一格，
  单格时直接返回该徽标、两格时 Row 并排，不叠同一优先级抢位置。
- 紧凑档 `_CompactTopBar` 改显当前页名：home 组合根经 01 映射 `teacherPageFace`/
  `childPageFace` 换算后由 `AdaptiveShell.currentTitle` 传入；取代写死且对教师端错误的
  「学生学习」；下钻页自然显示自身名（`_teacherPage` 已是导航栈顶派生，含 `ClassStudentsPage`
  的班级名）；长名 `Flexible + ellipsis` 截断不溢出。顶栏标题 `Key('compact-current-title')`
  供测试稳定定位。
- ⚠️ 冷启动未主动打任务接口拉计数（避免改动启动取数、避免测试未 override repo 触发网络）；
  教师打开过任务页后计数驻留 provider（非 autoDispose）跨页常驻。后续若要求首屏即见，
  可在 teacher 端 initState 触发一次 draft Tab 加载（需同步 override 测试 repo）。
- 测试：`test/nav_badge_and_title_test.dart`（9 例，含单元断言分槽并存 + widget 断言
  徽标随计数出现/消失、顶栏跟随切页与下钻班级名）。
- 全量 `flutter test` 604 passed；`flutter analyze` 无告警；
  `file_size_guard` 棘轮：adaptive_shell 531→544、home_screen 628→638（B 类真实增长，已调基线）。

## 纪律

- 徽标是**信号**不是装饰：只给「不处理就会堆积」的量（草稿、待办），不给静态总量。
- 标题取值必须来自 01 的映射，本票不得再手写一份 `switch (page) => 文案`。
