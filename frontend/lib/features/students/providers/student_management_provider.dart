import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import '../presentation/providers/student_management_notifier.dart';
import './students_provider.dart';

/// 学生管理页组合根：同时注入学生仓库与班级仓库（分组头 + 筛选都依赖班级）。
///
/// 与 `studentsProvider` 共用同一份 [studentsRepositoryProvider] 实例，
/// 不另开全局学生列表状态——管理页只在此处按需加载，避免与 14/15 的全局状态重构冲突。
final studentManagementProvider =
    StateNotifierProvider<StudentManagementNotifier, StudentManagementState>(
        (ref) {
  final studentsRepo = ref.watch(studentsRepositoryProvider);
  final classesRepo = ref.watch(classesRepositoryProvider);
  return StudentManagementNotifier(studentsRepo, classesRepo);
});
