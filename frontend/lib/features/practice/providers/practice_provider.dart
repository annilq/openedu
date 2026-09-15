import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/repositories/practice_repository_impl.dart';
import '../domain/repositories/practice_repository.dart';

/// 练习 feature 的**组合根**：把 `data/` 的实现绑到 `domain/` 的接口上。
///
/// 为什么不放在 `domain/`（会反向依赖 presentation）也不放在 `presentation/`
/// （会让 ViewModel 直接看见实现类）——理由见
/// `features/authentication/providers/auth_provider.dart` 的同名注释。
final practiceRepositoryProvider = Provider<PracticeRepository>((ref) {
  return PracticeRepositoryImpl(ref.watch(networkServiceProvider));
});
