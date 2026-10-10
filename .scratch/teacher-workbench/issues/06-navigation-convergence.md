# 06: 导航收敛（删 AnalyticsPage + 侧栏 + 测试）

**What to build:** 移除独立的「统计」侧栏入口，把工作台设为唯一 landing。删除 `AnalyticsPage` 子类、`teacher_destinations.dart` 对应入口、`home_screen.dart` 的 `AnalyticsPage()` 映射分支。扩展 `teacher_nav_single_source_test`：移除 `AnalyticsPage` 相关断言，确认 `OverviewPage` 为默认高亮且无双高亮漏清（ADR-0059 单源）。侧栏由 10 项降为 9 项，顺序不变（仅去「统计」）。

**Blocked by:** 05 (组合工作台，确保工作台已完整承载原统计能力后才去入口)

**Status:** done

- [ ] `AnalyticsPage` 子类、`teacher_destinations.dart` 入口、`home_screen.dart` 映射分支全部删除。
- [ ] 侧栏无「统计」项，共 9 项，顺序不变；`OverviewPage` 为默认高亮。
- [ ] `teacher_nav_single_source_test` 扩展：去 Analytics 断言 + 确认无双高亮漏清，测试通过。
- [ ] 全仓 grep 无 `AnalyticsPage` / `AnalyticsScreen` 残留引用；`flutter analyze` 无 issue。
