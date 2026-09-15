import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/repositories/question_bank_repository_impl.dart';
import '../data/repositories/task_review_repository_impl.dart';
import '../data/repositories/tasks_repository_impl.dart';
import '../domain/repositories/question_bank_repository.dart';
import '../domain/repositories/task_review_repository.dart';
import '../domain/repositories/tasks_repository.dart';

/// home feature 的**组合根**。选址理由见
/// `features/authentication/providers/auth_provider.dart` 的同名注释。
final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  return TasksRepositoryImpl(ref.watch(networkServiceProvider));
});

final questionBankRepositoryProvider = Provider<QuestionBankRepository>((ref) {
  return QuestionBankRepositoryImpl(ref.watch(networkServiceProvider));
});

final taskReviewRepositoryProvider = Provider<TaskReviewRepository>((ref) {
  return TaskReviewRepositoryImpl(ref.watch(networkServiceProvider));
});
