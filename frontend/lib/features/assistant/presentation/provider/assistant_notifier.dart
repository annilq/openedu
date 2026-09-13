import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/providers/core_providers.dart';
import '../../data/assistant_api_client.dart';
import '../../domain/ai_text_fold.dart';
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

  /// 当前会话 id：首轮由后端 DONE 帧回写，之后每轮原样带回以续接上下文。
  ///
  /// 后端对该 id 做「parent_id + child_id」归属校验（`features/assistant/service.py`）：
  /// 不匹配时不报错，而是**另建会话并回写新 id**，这里随之覆盖（自愈，不会读到他人会话）。
  /// 进程内有效；重启 App 会重新建会话（持久化另议）。
  String? _currentSessionId;

  /// 兜底历史上限，对齐后端 `load_chat_history(limit=20)`。
  ///
  /// 后端只有在「无 session_id」或「归属校验失败」时才消费请求里的 history
  /// （有有效 session_id 时改从 DB 载入并覆盖）。该兜底路径**没有服务端截断**，
  /// 所以必须在发送侧限长，否则长对话会把整段历史灌进 prompt。
  static const _historyLimit = 20;

  /// 把气泡列表压成后端契约的 history（`{"role", "content"}`），只保留最近 [_historyLimit] 条。
  List<Map<String, dynamic>> _tailHistory(List<AssistantMessage> messages) {
    final pairs = messages
        .where((m) => !m.thinking)
        .map((m) => {
              // UI 侧 role 是 'ai'，后端契约是 'assistant'（agent_core/ports.py）；
              // 键名是 content 而非 text——否则适配器取不到文本，整条被丢弃。
              'role': m.role == 'ai' ? 'assistant' : 'user',
              'content': m.text,
            })
        .toList();
    if (pairs.length <= _historyLimit) return pairs;
    return pairs.sublist(pairs.length - _historyLimit);
  }

  /// 发送一条消息并消费 SSE 事件流。角色由后端 JWT 解析（家长 / 娃娃自动分流）。
  Future<void> send(String raw, {String? model}) async {
    final message = raw.trim();
    if (message.isEmpty || _submitting) return;
    _submitting = true;

    final history = switch (state) {
      AssistantActive(:final messages) => _tailHistory(messages),
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
        AssistantChatReq(
          message: message,
          sessionId: _currentSessionId,
          history: history,
          model: model,
        ),
      )) {
        // 会话身份随 DONE 帧回写：首轮建立；归属校验失败时后端换新 id，此处自愈覆盖。
        if (ev.eventType == AssistantEventType.done && ev.sessionId != null) {
          _currentSessionId = ev.sessionId;
        }
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

  /// 开启新会话：丢弃当前 session_id 与气泡，下一轮重新在后端建立会话。
  ///
  /// 没有这一步 session_id 会一直续接，历史只增不减（后端仅截最近 20 条喂 prompt，
  /// 但会话本身不会结束）。UI 需要「新对话」入口时调用。
  void reset() {
    _currentSessionId = null;
    state = const AssistantInitial();
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
