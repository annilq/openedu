# 07: 文件规模护栏 ADR-0058 基线调低

**What to build:** 合并拆子文件后，使 `test/file_size_guard_test.dart` 的规模护栏重新达标。把主文件 `teacher_overview_view.dart`（工作台壳，只做组合与状态路由）的 `_baseline` 调低到拆分后的实际行数；为 `analytics_charts.dart` / `workbench_glance.dart` / `workbench_analysis.dart` 各自登记基线。护栏是 ADR-0058 硬约束（新文件 ≤400 行、单文件只暴露一个公开物），拆完必须让其重新通过，否则 CI 阻断。

**Blocked by:** 05 (组合工作台，子文件拆分已落定后才有真实行数)

**Status:** done

- [ ] `test/file_size_guard_test.dart` 的 `_baseline` 调低到拆分后主文件实际行数。
- [ ] `analytics_charts.dart` / `workbench_glance.dart` / `workbench_analysis.dart` 各自登记基线，均 ≤ 护栏阈值。
- [ ] `file_size_guard_test` 通过；每个子文件只暴露一个公开物（适配器层例外：同组图表 widget 视为一类职责）。
- [ ] `flutter analyze` 无 issue。
