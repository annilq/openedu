import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/datasource/auth_remote_data_source.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../domain/repositories/auth_repository.dart';
import '../presentation/providers/auth_notifier.dart';

/// 认证 feature 的**组合根**（composition root）。
///
/// 放在 `features/authentication/providers/` 而不是 `domain/providers/` 或
/// `presentation/providers/`，是因为它的职责天生跨层：把 `data/` 的实现
/// （[AuthRepositoryImpl]）绑到 `domain/` 的接口（[AuthRepository]）上，
/// 再注入 `presentation/` 的 [AuthNotifier]。
///
/// 塞进 `domain/` 会让 domain 反向依赖 presentation（依赖方向倒置）；
/// 塞进 `presentation/` 会让 ViewModel 层直接看见 DataSource。
/// 组合根不属于任何一层，所以单独占一个与 `data|domain|presentation` 平级的目录。
/// 由 `test/feature_boundaries_test.dart` 的 R4 / R5 守卫。

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  final dataSource = AuthRemoteDataSource(network);
  return AuthRepositoryImpl(dataSource, storage, network);
});

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(repo);
});
