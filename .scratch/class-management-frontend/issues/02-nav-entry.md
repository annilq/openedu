# Ticket 02 — 一级导航「班级管理」落地

- **What to build**: 扩展 `sealed TeacherPage` 增加 `classManagement` case（ADR-0059 导航单源纪律），新增一级导航项「班级管理」，与「学生管理」并列，不取代它。所有入口只调 `_go(page)`，禁止再开并行状态。
- **Blocked by**: —
- **Status**: ready-for-agent
- **验收清单**:
  - `sealed TeacherPage` 新增 `classManagement`；所有导航入口（侧栏/抽屉/底部栏）只经 `_go(page)` 切换到该页，无并行状态变量。
  - 沿用 `teacher_nav_single_source_test.dart` 的既有断言，补充新 case：新增导航项存在且经单源切换；不存在两个并行的"当前页"状态。
  - `flutter analyze` 零错误（残留旧导航状态即漏改）。
  - 自适应布局纪律（ADR-0045/0059）：窄屏走底部栏/抽屉、宽屏走侧栏，与既有页一致。
  - 全站禁 Material 控件：新增导航项在不套 Material 的树里真构建验证。
