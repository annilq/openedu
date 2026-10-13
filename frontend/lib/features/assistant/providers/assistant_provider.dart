import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/assistant_api_client.dart';
import '../data/repositories/assistant_repository_impl.dart';
import '../domain/repositories/assistant_repository.dart';

// —— 任务生成的公共契约（LCC-03）——
//
// 其它特性（如 home 的 TaskGenNotifier）只应 import 本 provider 模块，不得穿透到
// `domain/` 内部。这里统一把任务生成需要的公开类型从 assistant 的公共 API 暴露出去，
// 避免 home 直接 import `features/assistant/domain/*`（ADR-0059 层纪律：特性间只认
// 对方公共端口）。home 经由 [assistantRepositoryProvider] 取仓库实例，经下方类型
// 构造请求与折叠事件流。
export '../domain/assistant_requests.dart' show TaskGenerateReq;
export '../domain/question_gen_fold.dart' show QuestionGenFold;
export '../domain/repositories/assistant_repository.dart'
    show AssistantRepository, ScheduledDeleteHandle;

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
