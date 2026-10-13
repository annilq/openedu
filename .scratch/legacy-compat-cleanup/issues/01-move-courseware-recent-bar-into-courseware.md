# 01: 把 CoursewareRecentBar 搬进 courseware 特性

**What to build:** 课件中心的"最近课件"捷径条不再作为 home 的内部控件存在；courseware 特性改为引用自己特性内的该控件，home 大盘改为前向引用（组合根启动特性屏，合法）。结果：消除 home↔courseware 依赖环的一条回边。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `CoursewareRecentBar` 的定义文件位于 `features/courseware/presentation/widgets/` 之下。
- [ ] `courseware_center_screen` 从本特性内部引用它（不再 `import 'package:kids_learn/features/home/...'`）。
- [ ] home 的 `material_knowledge_manage_view` 仍能前向引用到该控件（组合根 → 特性，方向合法）。
- [ ] 定向 grep 确认：courseware 任何文件不再 import `package:kids_learn/features/home`。
- [ ] `flutter analyze`（含 `no_proxy` 环境）通过。

_— 定位（volatile，仅供本次实施）—_
- 定义：`frontend/lib/features/home/presentation/widgets/teacher/courseware_recent_bar.dart`
- 回边：`courseware_center_screen.dart:18`（from home）、`:42` 使用
- home 侧引用：`material_knowledge_manage_view.dart:17`（相对 import）、`:75` 使用
