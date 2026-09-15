import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/repositories/models_repository_impl.dart';
import '../domain/repositories/models_repository.dart';

/// 模型管理 feature 的**组合根**。选址理由见
/// `features/authentication/providers/auth_provider.dart` 的同名注释。
final modelsRepositoryProvider = Provider<ModelsRepository>((ref) {
  return ModelsRepositoryImpl(ref.watch(networkServiceProvider));
});
