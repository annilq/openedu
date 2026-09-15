import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/repositories/review_repository_impl.dart';
import '../domain/repositories/review_repository.dart';

/// 复习 feature 的**组合根**。选址理由见
/// `features/authentication/providers/auth_provider.dart` 的同名注释。
final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepositoryImpl(ref.watch(networkServiceProvider));
});
