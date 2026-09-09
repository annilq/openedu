import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/providers/core_providers.dart';
import '../../data/assistant_api_client.dart';
import '../../domain/assistant_event.dart';

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

  AssistantMessage copyWith({
    String? text,
    bool? blocked,
    List<Map<String, dynamic>>? cards,
    bool? thinking,
  }) =>
      AssistantMessage(
        role: role,
        text: text ?? this.text,
        blocked: blocked ?? this.blocked,
        cards: cards ?? this.cards,
        thinking: thinking ?? this.thinking,
      );
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
    current.add(const AssistantMessage(role: 'ai', thinking: true));
    state = AssistantActive(current, true);

    try {
      await for (final ev in _client.streamChat(
        AssistantChatReq(message: message, history: history, model: model),
      )) {
        _apply(ev, current);
        state = AssistantActive(List<AssistantMessage>.from(current), true);
      }
      state = AssistantActive(
        List<AssistantMessage>.from(_finalize(current)),
        false,
      );
    } catch (e) {
      final cleaned = _finalize(current);
      cleaned.add(AssistantMessage(role: 'ai', text: '⚠️ ${e.toString()}'));
      state = AssistantActive(cleaned, false, error: true);
    } finally {
      _submitting = false;
    }
  }

  List<AssistantMessage> _finalize(List<AssistantMessage> msgs) =>
      msgs.where((m) => !m.thinking).toList();

  void _apply(AssistantEvent ev, List<AssistantMessage> msgs) {
    switch (ev.eventType) {
      case AssistantEventType.assistantMessage:
        _appendAiText(msgs, ev.text ?? '');
      case AssistantEventType.data:
        _attachCard(msgs, ev);
      case AssistantEventType.error:
        msgs.removeWhere((m) => m.thinking);
        msgs.add(AssistantMessage(
          role: 'ai',
          text: ev.message ?? '出错了，请稍后重试',
          blocked: ev.code == 'INPUT_UNSAFE',
        ));
      case AssistantEventType.done:
        // 收尾：无额外动作，_finalize 会在流结束后清掉 thinking 占位。
        break;
      default:
        // THINKING / TOOL_CALL / TOOL_RESULT / STEP / RUN_STARTED：暂不单独渲染。
        break;
    }
  }

  void _appendAiText(List<AssistantMessage> msgs, String delta) {
    if (msgs.isEmpty) {
      msgs.add(AssistantMessage(role: 'ai', text: delta));
      return;
    }
    final last = msgs.last;
    if (last.role == 'ai') {
      msgs[msgs.length - 1] = last.copyWith(
        text: last.text + delta,
        thinking: false,
      );
    } else {
      msgs.add(AssistantMessage(role: 'ai', text: delta));
    }
  }

  void _attachCard(List<AssistantMessage> msgs, AssistantEvent ev) {
    final data = ev.data ?? {};
    final result = data['result'];
    if (result is! Map<String, dynamic>) return;
    if (msgs.isEmpty) {
      msgs.add(AssistantMessage(role: 'ai', cards: [result]));
      return;
    }
    final last = msgs.last;
    if (last.role == 'ai') {
      final cards = List<Map<String, dynamic>>.from(last.cards ?? [])..add(result);
      msgs[msgs.length - 1] = last.copyWith(cards: cards, thinking: false);
    } else {
      msgs.add(AssistantMessage(role: 'ai', cards: [result]));
    }
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
