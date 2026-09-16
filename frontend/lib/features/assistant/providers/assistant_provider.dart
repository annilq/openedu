import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/assistant_api_client.dart';
import '../data/repositories/assistant_repository_impl.dart';
import '../domain/repositories/assistant_repository.dart';

/// assistant feature 的**组合根**。选址理由见
/// `features/authentication/providers/auth_provider.dart` 的同名注释。
///
/// 原先 `assistantApiClientProvider` 定义在 `presentation/provider/assistant_notifier.dart`
/// 里，导致展示层直接 import `data/`；搬到组合根后，home 与 assistant 的
/// ViewModel 都只认 [assistantRepositoryProvider] 这个领域端口。
final assistantApiClientProvider = Provider<AssistantApiClient>((ref) {
  return AssistantApiClient(ref.watch(networkServiceProvider));
});

final assistantRepositoryProvider = Provider<AssistantRepository>((ref) {
  return AssistantRepositoryImpl(
    ref.watch(assistantApiClientProvider),
    // 会话历史走普通请求（非流），与事件流共用同一个网络服务实例。
    ref.watch(networkServiceProvider),
  );
});
