import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'class_management_notifier.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/shared/domain/models/class_model.dart';
import 'package:kids_learn/shared/presentation/resource.dart';

/// 班级管理页的组合根（ADR-0086）。
///
/// 复用既有的 [classesRepositoryProvider]（学生管理页也用它拉班级列表），
/// 只为这个页面新开一条 `ClassManagementNotifier` 状态线，避免再养一份全局班级列表。
final classManagementProvider =
    StateNotifierProvider<ClassManagementNotifier, Resource<List<ClassModel>>>(
  (ref) => ClassManagementNotifier(ref.watch(classesRepositoryProvider)),
);
