# 09: 折叠 home 导航三元组为 sealed 单源

**What to build:** `home_screen` 中 `bool _showProfile` 与 `_childNavIndex` 并存的"索引+布尔"双真源，折叠为 ADR-0059 要求的单一 sealed 导航状态；消除与自身头注释矛盾的死设计。

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 代码中不存在 `_showProfile` 布尔字段（grep `_showProfile|_childNavIndex` 在 `lib/` 零字段命中；仅历史注释与测试反向断言提及）。
- [x] 激活页只由 sealed 导航状态决定：`_teacherPage`(`TeacherPage`) / `_childPage`(`ChildPage`) 单源，ADR-0059。
- [x] `flutter analyze` 绿；导航测试 `test/teacher_nav_single_source_test.dart:58-84` 断言禁用字段不出现且 `TeacherPage _teacherPage` 存在。

_— 核验（2026-10-14，交叉核验发现 tracker 陈旧）—_
- 实现已在 main：`2a7e1d4 refactor(home): collapse student nav into sealed ChildPage single source (LCC-09, ADR-0059)`；`git log main..HEAD` 对 home_screen / child_pages / teacher_pages / 导航测试为空 → 早已合入 main，非本 integration 分支增量。
- 原「定位」已陈旧：`home_screen.dart:65` 实为 `TeacherPage _teacherPage`（sealed 单源），`:69` 为 `ChildPage _childPage`；`_showProfile` / `_childNavIndex` 仅是头注释里「被取代」的反面教材，代码与索引字段均不存在。
- 参考既有 sealed 导航：`frontend/lib/main`（TeacherPage / AdaptiveShell）单态约定，ADR-0059。
