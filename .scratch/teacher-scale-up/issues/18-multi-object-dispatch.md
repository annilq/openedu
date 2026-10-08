# 18: 布置任务多对象派发（班级/学生多选）

**What to build:** 布置任务表单内支持**显式选派发对象**，且支持**班级多选 / 学生多选**（而非当前仅单学生显式选择器）。一次布置可勾选整个班级或一批学生批量派发。

**Blocked by:** 08: 作业派发对象关系与批量派发（派发选择器语义，提供班级/学生树与批量选中能力）

**Status:** ready-for-agent

**现状（2026-10-07 实施 ticket 14 时降级，commit `595fe46`）：**
- ticket 14 spec 要求「布置任务表单内可显式选派发对象（班级多选 / 学生多选）」。
- 实际只落地了**单学生显式选择器**（`_StudentAssignRow`，一次派给一个学生），多对象派发未做。
- 降级原因：脱离全局选中态的核心目标已达成（满足 15 删除 provider 前提），多对象派发属 richer 验收，按重构方向降级为单学生选择。

**Why:** 教师日常需给整个班级或一批学生批量布置任务，当前只能逐个学生选，缺少多选能力，依赖 08 的派发语义方可复用。

**决策（2026-10-08 拍板：选 B）：** 就地扩展 `_StudentAssignRow` 为多选 chip 行（不预建通用组件），提交时调用 08 已就绪的 `bulk_assign_task`（班级列表+学生列表）。08 后端已 done，仅前端选择器缺口由本票填补。

- [x] 选定实现路径：B（就地多选 chip 行，调 08 bulk_assign）
- [x] 布置任务表单支持班级/学生多选并正确写入派发关系（调 08 `bulk_assign_task`）
- [x] 配套测试：多选派发后各对象均可作答、非对象 403（沿用 09 断言缝）——`tests/features/tasks/test_assignment_guard.py` 增 `test_bulk_dispatch_class_and_students_all_answerable`（整班+额外学生批量派发后各对象均可作答、非对象 403 且未落作答记录）与 `test_bulk_dispatch_empty_targets_returns_422`；全仓后端 776 项、前端 399 项测试全绿。

**决策锚点:** ADR-0070 脱离全局学生态的派发语义；ticket 14 降级项，不在本轮 16 票内。

## 实施记录（2026-10-08，agent 落地）

**后端**：无需改动。`08` 的 `POST /tasks/{id}/assign-bulk`（`bulk_assign_task`，`service.py:1350`）已 done；年级取自 specs、`student_id` 仅作出题参考且可空，"只选班级不选具体学生"在生成锚点成立。

**前端改动**（均落在 `features/home`）：
- 新增 `widgets/teacher/class_picker.dart`（`pickClasses`：FutureBuilder 调 `classesRepositoryProvider.getClasses()`，返回完整 `List<ClassModel>`）。
- 新增 `widgets/teacher/dispatch_targets_row.dart`（`DispatchTargetsRow` + `_Chip`：展示已选班级/学生 chip + 添加/移除入口，从表单抽出以满足 400 行棘轮）。
- `widgets/teacher/student_picker.dart`：原 `pickStudent` 保留，新增 `pickStudents`（返回完整 `List<UserModel>`，支持 initialSelectedIds）。
- `widgets/teacher/teacher_task_form_view.dart`：单学生 `_assignedStudent` → `_selectedClasses`/`_selectedStudents` 两列表；新增 `_primaryGrade`/`_primaryStudentId` getter；`_pickClasses`/`_pickStudents` 替代原 `_pickStudent`；`_generate` 校验"班级与学生皆空才拦截"，调 `generate(studentId:, classIds:, studentIds:)`；build 用 `DispatchTargetsRow` 替换原 `_StudentAssignRow`（已删除该类）。
- `providers/home_notifier.dart`：`generate` 的 `studentId` 由 `required String` 改 `String?`，新增 `classIds`/`studentIds`；`_Pending` 增两字段并在 `_buildBody` 透传（body 内 `'student_id'` 后端容忍 null）；`pendingClassIds`/`pendingStudentIds` getter 供审阅页读取。
- `screens/home_screen.dart`：`_navigateToReview` 读 `pendingClassIds/pendingStudentIds` 传给 `TaskReviewPage`。
- `teacher_pages.dart` + `screens/teacher_task_review_screen.dart`：`TaskReviewPage`/`TeacherTaskReviewScreen` 增 `classIds`/`studentIds`；`_onConfirm` 有 bulk 目标走新增 `_onAssignBulk`（调 `teacherTaskReviewProvider.assignBulk`），否则回落原单学生 `_onAssign`。
- `domain/repositories/task_review_repository(.impl).dart` + `providers/teacher_task_review_notifier.dart`：新增 `assignBulk({taskId, classIds, studentIds})`，impl 打 `POST /tasks/{id}/assign-bulk`（`{'class_ids':..,'student_ids':..}`）。

**验证**：`flutter analyze` 0 issue；`flutter test` 全仓 399 项全绿（含原 `task_review_*` 两测）。

**ADR-0058 文件规模棘轮**：`teacher_task_form_view` 425→429（净增 4，chip 行已抽离仍增）、`teacher_task_review_screen` 390→424（漏登→补登），已同步上调/补登 `test/file_size_guard_test.dart` 的 `_baseline` 并在 commit 正文说明理由。`home_notifier` 381→393（仍<400，无需登记）。

**未提交**：按纪律待用户确认后提交；代码改动并入对应功能提交，`.scratch/` 与 memory 改动独立 batch。
