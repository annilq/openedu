import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/repositories/tutor_logs_repository_impl.dart';
import '../domain/repositories/tutor_logs_repository.dart';

/// 答疑记录 feature 的**组合根**。选址理由见
/// `features/authentication/providers/auth_provider.dart` 的同名注释。
final tutorLogsRepositoryProvider = Provider<TutorLogsRepository>((ref) {
  return TutorLogsRepositoryImpl(ref.watch(networkServiceProvider));
});
