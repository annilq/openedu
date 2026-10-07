# 13: 学生详情页（页签：概览/错题本/AI答疑）

**What to build:** 学生详情页，接收 `student_id` 参数（**不依赖全局学生状态**），以页签切换概览 / 错题本 / AI 答疑记录。列表行内入口直达此页错题页签。页签切换为**局部状态**，禁止提升为全局状态，避免「看着 A 却按 B 出题」这类漏清 bug（ADR-0059 核心教训）。

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 点列表行进入对应学生详情页，页签可切概览 / 错题本 / AI 答疑
- [x] 页签切换不影响其他页面上下文（局部状态，不提升为全局）
- [x] 错题本 / AI 答疑数据按该学生加载（不再依赖全局「当前学生」）
- [x] 详情页在「不套 Material」的树里真构建通过
- [x] 行内直达入口正确带 `student_id` 落到错题页签

**Done note (2026-10-07):** `teacher_pages.dart` 新增 `StudentDetailPage(studentId, initialTab)` +
`StudentDetailTab` 枚举；`student_detail_screen.dart` 用局部 `_tab` 状态切换三页签（概览进度快照 +
快捷入口 / 错题本 / AI 答疑），`initState` 按 studentId 加载三页签数据，不读 `selectedStudentProvider`；
`TeacherWrongQuestionsView` / `TeacherTutorLogsView` 加可选 `studentId` 参数（为空退回全局态，侧栏旧入口不变）；
`home_screen.dart` `_buildTeacherPage` 增 case，`TeacherStudentSelector` 每行加「查看详情」(`LucideIcons.eye`)
内联入口直达错题本页签。`flutter analyze lib` 0 issue；`teacher_nav_single_source_test` 5 passed；
新增 `student_detail_screen_test` 1 passed（非 Material 树构建 + 页签局部切换）。

**决策锚点：** ADR-0070「导航状态」；学生详情页页签是局部状态，新增「学生详情（带学生 ID）」页面状态到教师端唯一 sealed 导航。与 14 协同：详情页先就位，14 再把全局入口移除并指向它。

**Verification (2026-10-07):** 对照 `student_detail_screen.dart` 与 `teacher_destinations.dart:55-64` 复核：`StudentDetailPage(studentId, initialTab)` 收 studentId、局部 `_tab` 切换三页签；侧栏「学生」入口已加。`Status: done` 与代码一致，无需改动。
