# 05: 组合工作台 teacher_overview_view.dart + 删重复 provider

**What to build:** 把「概览」页重组为三段式教师工作台：任务区（保留现有待办 + 最近任务 + 学生总数徽标）+ 速览层（03）+ 分析层（04）。删除 `teacherOverviewProvider`/`TeacherOverviewNotifier`——它重复消费 `analyticsRepository`（写死 `scope=all` 参数版），与统计页同源，违反 ADR-0059 单源精神；工作台统一复用 `analyticsNotifier`。UI 标题改为「工作台」，仍作为 `TeacherPage` 唯一 landing 状态。注意 `task_empty_state_test` 仍引用 `TeacherOverviewView`，不得破坏。

**Blocked by:** 03 (速览层), 04 (分析层)

**Status:** ready-for-agent

- [ ] `teacher_overview_view.dart` 组合三段：任务区 + 速览层 + 分析层；默认进入即见速览。
- [ ] `teacherOverviewProvider`/`TeacherOverviewNotifier` 已删除；工作台取数只经 `analyticsNotifier`，无重复请求。
- [ ] UI 标题为「工作台」；`TeacherPage` sealed 单源导航不变。
- [ ] `task_empty_state_test` 仍通过（仍引用 `TeacherOverviewView`）；`flutter analyze` 无残留引用。
- [ ] 长页采用分区 / 速览层与分析层 sticky section header + 锚点跳转，避免滚动疲劳。
