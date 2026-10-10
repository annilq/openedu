# 01: 基座——引入 fl_chart + Material 祖先冒烟测试 gate

**What to build:** 为教师工作台图表化建立依赖基座。把 `fl_chart` 加入前端依赖并 `pub get` 成功；在本工程**禁用 Material 控件**的约束下，写一个最小空构建冒烟测试——在 `ShadApp`/`CupertinoApp` 根树（无 Material 祖先）中挂载一个 fl_chart 图表，证明它不内部引用任何 Material widget（否则构建期即崩「No Material widget found」，ADR-0075 §2.3 强制 gate）。同步在代码库中预留图表适配器目录（`analytics_charts.dart`），但本张不做图表实现。

**Blocked by:** None (can start immediately)

**Status:** done

- [ ] `flutter pub get` 成功，`fl_chart` 进入 `pubspec.yaml` 依赖。
- [ ] 冒烟测试在非 Material 根树下挂载 fl_chart 并通过（不抛「No Material widget found」）。
- [ ] 冒烟测试作为 CI 可重复跑的 gate，记录失败即阻断后续图表 ticket 的结论。
- [ ] 图表适配器文件 `analytics_charts.dart` 已建占位（含 `AppBarChart`/`AppDonutChart`/`AppGroupedBarChart`/`AppStackedBarChart` 的待实现骨架注释），供 02 填充。
- [ ] `flutter analyze` 无 issue。
