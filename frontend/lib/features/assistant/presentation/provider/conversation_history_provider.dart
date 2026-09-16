import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/conversation.dart';
import '../../providers/assistant_provider.dart';

/// 家长的历史会话列表（ADR-0048）。
///
/// 用 `FutureProvider` 而非 Notifier：这是**无状态的读**，唯一需要的操作是「重新取」
/// （新建 / 续接一段会话之后），而那正是 `ref.invalidate`——为它造一个 StateNotifier
/// 只会多出一份与本 provider 同义的缓存。
final conversationHistoryProvider =
    FutureProvider<List<AssistantConversation>>((ref) async {
  return ref.watch(assistantRepositoryProvider).conversations();
});
