import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/datasource/students_remote_data_source.dart';
import '../data/repositories/students_repository_impl.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import '../presentation/providers/students_notifier.dart';

/// 学生管理 feature 的**组合根**（composition root）。选址理由见
/// `features/authentication/providers/auth_provider.dart` 的同名注释：
/// 装配代码跨 `data/domain/presentation` 三层，塞进任何一层都会造成依赖倒置，
/// 因此单独占一个平级目录。由 `test/feature_boundaries_test.dart` 的 R4 / R5 守卫。

final studentsRepositoryProvider = Provider<StudentsRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  final dataSource = StudentsRemoteDataSource(network);
  return StudentsRepositoryImpl(dataSource);
});

final studentsNotifierProvider =
    StateNotifierProvider<ChildrenNotifier, ChildrenState>((ref) {
  final repo = ref.watch(studentsRepositoryProvider);
  return ChildrenNotifier(repo);
});
