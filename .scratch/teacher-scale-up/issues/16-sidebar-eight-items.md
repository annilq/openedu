# 16: 侧栏入口调整（移除顶部选择器，新增学生/统计）

**What to build:** 移除侧栏顶部学生选择器整体（切换 / 添加 / 编辑三件事一起走，不做降级保留）。新增「学生」与「统计」两项入口。教师端导航仍是唯一的 sealed 状态，新增「学生管理」与「学生详情（带学生 ID）」两个页面状态。

**侧栏实际项数（2026-10-07 核实）：九项** —— 概览 / 任务 / 布置任务 / **学生** / **统计** / 题库 / 资料库 / 模型管理 / **课件**。其中「课件」是 ADR-0067 课件工作流的产出，**不归本 ticket**；本票只负责「学生」「统计」两项入口可达 + 顶部选择器移除。原 spec 写「八项」基于「课件不存在」假设，已随 ADR-0067 落地失效，故修正为九项。

**Blocked by:** 15: 删除全局 selectedStudentProvider（全局状态移除后顶部选择器才能删）

**Status:** done

- [x] 侧栏已含「学生」「统计」入口，可达对应页（`teacher_destinations.dart:55-64`）
- [x] 顶部选择器文件已删除（`teacher_student_selector.dart` 已从 git 移除）
- [x] 全局 `selectedStudentProvider` 删除后，顶部选择器残留浮层彻底消失（依赖 15）
- [x] 导航状态仍为唯一 sealed，新增页面状态已登记
- [x] 扩展既有 `teacher_nav_single_source_test.dart` 覆盖新增两个页面状态，不新建测试缝
- [x] 移除顶部选择器后 `flutter analyze` 零错误

**Done note (2026-10-07):** 收尾落地：① 顶部选择器残留浮层已随 15 删 `selectedStudentProvider` 消失（`selectedStudentProvider` 仅剩注释引用，`teacher_student_selector.dart` 已从 git 移除）；② `TeacherPage`（`teacher_pages.dart:16`）已是 sealed，且已含 `StudentManagementPage`/`StudentDetailPage` 两分支，`home_screen.dart` 的 sealed switch 穷尽接线；③ `teacher_nav_single_source_test.dart` 新增两用例，真构建覆盖「学生」入口（`StudentManagementPage`）与 drill 进学生详情（`StudentDetailPage`，侧栏零高亮），共 7 例全过；④ `flutter analyze` 零 error。附带修 `analytics_screen_test` 的 `_FakeStudentsRepository` 补 `importStudents`（ticket 06 给 `StudentsRepository` 抽象加方法后的遗留缺口）。

**决策锚点：** ADR-0070；顶部选择器与全局状态一体移除（15 已删 provider，本 ticket 收尾 UI）。C6（概览改教师工作台）按 spec 建议先出原型、延后单独排期，不在本轮 16 票内。
