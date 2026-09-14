import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/storage_service.dart';
import '../../data/remote/dio_network_service.dart';
import '../../data/remote/network_service.dart';
import '../../../services/auth_session/domain/providers/auth_guard_provider.dart';

/// StorageService — 全局单例，App 启动时初始化。
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Must override in ProviderScope');
});

/// NetworkService — Dio 实现，注入 StorageService 做 token 拦截。
/// 401（token 过期/失效）经 [authExpiredProvider] 通知全局跳登录。
final networkServiceProvider = Provider<NetworkService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final authGuard = ref.watch(authExpiredProvider.notifier);
  return DioNetworkService(storage, onUnauthorized: authGuard.signal);
});
