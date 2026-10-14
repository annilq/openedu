# 10: 学生与班级管理合并为一个入口

**What to build:** 找学生只有一条路径。侧栏「班级」页内可切「按班级 / 全部学生」两种视图，学生详情的返回落点唯一——不再有两条到达同一个学生、返回却落到不同地方的情况。

**Blocked by:** 03（返回栈：合并后返回落点不再靠各页面自己声明）

**Status:** done

## 验收

- [x] 侧栏只剩一个承载学生的入口（「班级」，图标 `LucideIcons.school`；原「学生」「班级管理」两项合并）
- [x] 页内可在「按班级 / 全部学生」两种视图间切换，切换不清空筛选与关键字（`IndexedStack` 常驻双视图）
- [x] 从班级下钻进学生详情，返回回**班级视图**而非全部学生（`studentsEntryViewProvider` 还原进入前视图）
- [x] 从全部学生进学生详情，返回回**全部学生**
- [x] 班内新建学生的保存回落页唯一（回该班视图）（下钻/返回落点由历史栈决定，单一出口）
- [x] 合并后不存在两条到达同一学生详情的入口（入口唯一，`StudentDetailPage` 仅经 `StudentsScreen.onOpenStudent` 进入）
- [x] widget 测试：两种来源进入学生详情，返回各自回落正确（`teacher_nav_single_source_test` 三组真点 + `teacher_nav_stack_test` 栈行为）

## 落地要点

- 视图态不放进 `StudentsPage` 导航对象（否则切页内 tab 改变 `_teacherPage` 触发壳内 150ms 换页转场 + 污染 ADR-0059 单源）；改用 `studentsEntryViewProvider`（`StateProvider<StudentsView>`）。
- 新增 `students_container_screen.dart`（`StudentsScreen`，~82 行，低于 ADR-0058 400 行基线）。
- 侧栏清单测试由 9 项减为 8 项；`teacher_nav_single_source_test` 顺带修复陈旧「学生」侧栏标签断言为「班级」。

## 纪律

- 班级是容器、学生是内容——入口以容器为主，内容作为视图切换，不得反过来。
- 本票不动后端班级 / 学生模型，只收敛前端入口与返回落点。
