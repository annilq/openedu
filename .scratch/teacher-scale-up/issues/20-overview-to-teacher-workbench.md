# 20: 概览页改教师工作台（待办聚合）

**What to build:** 把概览页从「全班聚合视角」升级为**教师工作台**——聚合待派发 / 待审核 / 谁没交 + 全班速览，形成教师进入 App 的首屏待办中心。

**Blocked by:** 11: 学情统计聚合端点（聚合数据来源）；12: 统计页 UI（可复用其卡片/聚合展示范式）

**Status:** ready-for-agent

**现状（2026-10-07 实施 ticket 14 时）：**
- ticket 14 的概览**已**改为教师整体视角（全班聚合：已掌握 / 活跃错题 / 薄弱知识点），脱离全局学生态。
- 但 C6「概览改教师工作台」是更进一步的形态——增加**待办聚合**（待派发 / 待审核 / 谁没交），而非仅学情聚合。
- INDEX 第 33 行明确：C6 按 spec 建议**先出原型、延后单独排期，不在本轮 16 票内**。

**Why:** 教师首屏需要一眼看到「哪些任务没派发完、哪些待我审核、哪些学生没交」，当前概览只展示学情聚合，缺待办入口。聚合维度依赖 11 的学情/派发聚合端点与 12 的统计展示范式。

**决策（2026-10-08 拍板：选 A）：** 在现有概览顶部加三张待办卡片（待派发 / 待审核 / 谁没交），点击直达对应列表（任务列表 10 / 审核流），复用 12 统计页展示范式。B 拆栏重构留作后续独立项。

- [x] 选定实现路径：A（顶部三卡片）
- [x] 三张待办卡片聚合并深链对应列表：
  - 后端 `GET /tasks/teacher-todo-summary`（`TeacherTodoSummary{pending_review,pending_dispatch,not_submitted}`）；
  - 待审核=`count_tasks_by_teacher_grouped` 的 `draft`、待派发=`ready`、谁没交=新增 `count_incomplete_assignments_by_teacher`（join `Task.teacher_id` 收敛未完成派发）；
  - 前端概览页 `TeacherTodoCards` 三卡并排，点击经 `TaskListPage(initialTab)` → `TeacherTasksView(initialTab)` 深链到任务列表 Tab（待审核/待派发→Tab0 草稿箱，谁没交→Tab1 进行中）。
- [x] 不影响现有学情聚合布局（待办区插在头部与「掌握度概览」之间，既有三个区块未动）。

**决策锚点:** ADR-0070 教师端导航与学情聚合；INDEX C6 延后项，不在本轮 16 票内。

**落地状态（2026-10-08）：** 后端 schema/repository/service/router + 测试 9 项全绿；前端模型/repo/provider/卡片/区块四件套 + `initialTab` 深链；`flutter analyze` 0 issue、`flutter test` 399 全绿；`teacher_tasks_view.dart` 棘轮基线 649→656（功能必需，已注明）。
