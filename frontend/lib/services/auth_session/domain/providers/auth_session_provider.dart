import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../data/repositories/auth_session_repository_impl.dart';
import '../../domain/repositories/auth_session_repository.dart';

final authSessionRepositoryProvider = Provider<AuthSessionRepository>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final network = ref.watch(networkServiceProvider);
  return AuthSessionRepositoryImpl(storage, network);
});

/// 当前登录用户状态：App 启动时从本地存储恢复，登录/登出时更新。
final currentUserProvider = StateProvider<UserModel?>((ref) => null);

/// 是否已登录
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});
