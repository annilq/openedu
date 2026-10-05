import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/repositories/material_repository_impl.dart';
import '../domain/repositories/material_repository.dart';
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

final materialRepositoryProvider = Provider<MaterialRepository>((ref) {
  return MaterialRepositoryImpl(ref.watch(networkServiceProvider));
});

/// 知识点选择器数据源（ADR-0055 §4）：按 (subject, grade, semester) 取「涌现目录 + 骨架兜底」。
/// 表单每行按学科×年级×学期联动取选项；autoDispose 随行卸载，不缓存陈旧目录。
///
/// 学期进key（ADR-0061 发布任务对接资料库）：同一知识点可按学期分设模板，家长选了
/// 「上学期」就只看到上学期的目录，讲解时才不会拿错学期的交互场景。
final knowledgePointsProvider = FutureProvider.autoDispose
    .family<List<KnowledgePointOption>, (String, int, String)>((ref, key) async {
  final (subject, grade, semester) = key;
  final repo = ref.watch(materialRepositoryProvider);
  return repo.getKnowledgePoints(
    subject: subject,
    grade: grade,
    semester: semester,
  );
});
