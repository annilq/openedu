# 15: 删除全局 selectedStudentProvider

**What to build:** 彻底删除全局 `selectedStudentProvider` 及其所有引用。spec 明确**反对过渡期两套事实源**（保留一个「当前学生」会让学生详情页和全局上下文成为两个事实源，一旦并列必然漏清且静态检查查不出），因此采用**一次切净**而非 expand-contract。

**Blocked by:** 14: 六处消费方脱离全局学生状态

**Status:** done

- [x] `flutter analyze` 零错误（残留引用即漏改）
- [x] 全局搜索 `selectedStudentProvider` 无结果
- [x] 六处消费方均不依赖全局学生状态
- [x] 学生详情页页签切换不污染其他页面
- [x] 扩展既有 `teacher_nav_single_source_test.dart` 覆盖新页面状态，确认单源导航不变量

**完成说明（commit 595fe46 / ae5a726，2026-10-07）：**
- 已 `git rm` `home/presentation/providers/selected_student_provider.dart`；全局搜索无残留引用。
- `home_screen` 删除 `_setCurrentStudent` 全局写入与重载；`tutor_logs`/`wrong_questions` 改为必须显式传 `studentId`。
- 两测试移除 provider override 并补 analytics stub；`list_density`+`task_empty`+`nav_single_source` 共 16 测试全绿。
- 按一次切净策略执行，未保留过渡期双事实源。

**决策锚点：** ADR-0070 + ADR-0059；与 skill 默认的 wide-refactor expand-contract 有偏差，已按 ADR 钉死为一次切除（保留两套是已知 bug 根源）。建议单独成一个提交批次（回归面最大）。
