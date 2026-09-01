import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/storage_service.dart';
import '../../data/remote/dio_network_service.dart';
import '../../data/remote/genkit_ai_client.dart';
import '../../data/remote/network_service.dart';

/// StorageService — 全局单例，App 启动时初始化。
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Must override in ProviderScope');
});

/// NetworkService — Dio 实现，注入 StorageService 做 token 拦截。
final networkServiceProvider = Provider<NetworkService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return DioNetworkService(storage);
});

/// GenkitAiClient — Genkit 全栈客户端（ADR-0015），直连后端原生 action 端点。
/// 依赖 StorageService 取出 Bearer token 逐次注入（Dart 原生 http.Client 不走 Dio 拦截器）。
final genkitAiClientProvider = Provider<GenkitAiClient>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return GenkitAiClient(storage);
});
