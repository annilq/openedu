import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/providers/core_providers.dart';
import '../../data/assistant_api_client.dart';
import '../../domain/ai_text_fold.dart';

/// 一条助手对话气泡。
class AssistantMessage {
  final String role; // 'user' | 'ai'
  final String text;
  final bool blocked;
  final List<Map<String, dynamic>>? cards; // DATA 结构化结果（题卡 / 任务卡）
  final bool thinking; // 占位「思考中」气泡（尚无文本）

  const AssistantMessage({
    required this.role,
    this.text = '',
    this.blocked = false,
    this.cards,
        this.thinking = false,
      });
}

sealed class AssistantState {
  const AssistantState();
}

class AssistantInitial extends AssistantState {
  const AssistantInitial();
}

class AssistantActive extends AssistantState {
  final List<AssistantMessage> messages;
  final bool streaming;
  final bool error;

  const AssistantActive(this.messages, this.streaming, {this.error = false});
}

class AssistantNotifier extends StateNotifier<AssistantState> {
  final AssistantApiClient _client;

  AssistantNotifier(this._client) : super(const AssistantInitial());

  bool _submitting = false;

  /// 发送一条消息并消费 SSE 事件流。角色由后端 JWT 解析（家长 / 娃娃自动分流）。
  Future<void> send(String raw, {String? model}) async {
    final message = raw.trim();
    if (message.isEmpty || _submitting) return;
    _submitting = true;

    final history = switch (state) {
      AssistantActive(:final messages) => messages
          .where((m) => !m.thinking)
          .map((m) => {'role': m.role, 'text': m.text})
          .toList(),
      _ => <Map<String, dynamic>>[],
    };

    final current = switch (state) {
      AssistantActive(:final messages) =>
        List<AssistantMessage>.from(messages.where((m) => !m.thinking)),
      _ => <AssistantMessage>[],
    };
    current.add(AssistantMessage(role: 'user', text: message));
    state = AssistantActive(current, true);

    // 事件解释委托 [AiTextFold]（纯模块）：本 notifier 只负责喂事件与落状态。
    var fold = const AiTextFold();
    try {
      await for (final ev in _client.streamChat(
        AssistantChatReq(message: message, history: history, model: model),
      )) {
        fold = fold.apply(ev);
        state = AssistantActive(_render(current, fold, streaming: true), true);
      }
      state = AssistantActive(_render(current, fold, streaming: false), false);
    } catch (e) {
      state = AssistantActive(
        <AssistantMessage>[
          ..._render(current, fold, streaming: false),
          AssistantMessage(role: 'ai', text: '⚠️ ${e.toString()}'),
        ],
        false,
        error: true,
      );
    } finally {
      _submitting = false;
    }
  }

  /// 把 [fold] 的解释结果渲染到气泡列表尾部：思考中占位 → 正文 → 错误气泡。
  ///
  /// 占位气泡只在 [streaming] 时存在；流结束（或异常）后必须消失，否则会留下
  /// 一个永久转圈的空气泡。
  List<AssistantMessage> _render(
    List<AssistantMessage> history,
    AiTextFold fold, {
    required bool streaming,
  }) {
    final out = List<AssistantMessage>.from(history);
    if (fold.isEmpty) {
      if (streaming) {
        out.add(const AssistantMessage(role: 'ai', thinking: true));
      }
      return out;
    }
    if (fold.text.isNotEmpty || fold.cards.isNotEmpty) {
      out.add(AssistantMessage(
        role: 'ai',
        text: fold.text,
        cards: fold.cards.isEmpty ? null : fold.cards,
        blocked: fold.blocked,
      ));
    }
    if (fold.hasError) {
      out.add(AssistantMessage(
        role: 'ai',
        text: fold.errorText!,
        blocked: fold.blocked,
      ));
    }
    return out;
  }
}

final assistantApiClientProvider = Provider<AssistantApiClient>((ref) {
  final network = ref.watch(networkServiceProvider);
  return AssistantApiClient(network);
});

final assistantNotifierProvider =
    StateNotifierProvider<AssistantNotifier, AssistantState>((ref) {
  final client = ref.watch(assistantApiClientProvider);
  return AssistantNotifier(client);
});
