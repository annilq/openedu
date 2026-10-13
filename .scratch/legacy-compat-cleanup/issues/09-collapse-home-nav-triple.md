# 09: 折叠 home 导航三元组为 sealed 单源

**What to build:** `home_screen` 中 `bool _showProfile` 与 `_childNavIndex` 并存的"索引+布尔"双真源，折叠为 ADR-0059 要求的单一 sealed 导航状态；消除与自身头注释矛盾的死设计。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 代码中不存在 `_showProfile` 布尔字段。
- [ ] 激活页只由 sealed 导航状态决定（与 `home_screen` 头注释声明的 sealed 单源一致）。
- [ ] `flutter analyze` + 导航相关测试通过。

_— 定位（volatile，仅供本次实施）—_
- `frontend/lib/features/home/presentation/screens/home_screen.dart:65`（`bool _showProfile`）、`:523-524`（`_childNavIndex`）
- 参考既有 sealed 导航：`frontend/lib/main`（TeacherPage / AdaptiveShell）单态约定，ADR-0059
