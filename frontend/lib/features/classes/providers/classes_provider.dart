import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/datasource/classes_remote_data_source.dart';
import '../data/repositories/classes_repository_impl.dart';
import '../domain/repositories/classes_repository.dart';

/// 班级 feature 的组合根（与 `students_provider.dart` 同款结构，ADR-0058）。
///
/// 只暴露 [classesRepositoryProvider]：班级取数被学生管理页（分组头 + 筛选下拉）
/// 复用，但本身不需要独立的全局列表状态——加载动作收进学生管理页的 notifier，
/// 避免再开一条会被 14/15 重构波及的全局状态。
final classesRepositoryProvider = Provider<ClassesRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return ClassesRepositoryImpl(ClassesRemoteDataSource(network));
});
