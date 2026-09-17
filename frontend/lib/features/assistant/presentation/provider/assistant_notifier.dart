import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/assistant_requests.dart';
import '../../domain/repositories/assistant_repository.dart';
import '../../providers/assistant_provider.dart';
import '../../domain/ai_text_fold.dart';
import '../../domain/assistant_card.dart';
import '../../domain/assistant_event.dart';
import '../../domain/conversation.dart';

/// 一条助手对话气泡。
class AssistantMessage {
  final String role; // 'user' | 'ai'
  final String text;
  final bool blocked;
  final List<AssistantCard>? cards; // DATA 类型化卡片（题卡 / 任务卡 / 学情卡）
  final bool thinking; // 占位「思考中」气泡（尚无文本）
  final String stage; // thinking 时的阶段文案（路由/工具帧提取），空 = 默认「思考中…」

  const AssistantMessage({
    required this.role,
    this.text = '',
    this.blocked = false,
    this.cards,
        this.thinking = false,
        this.stage = '',
      });

  /// 从回放气泡重建一条消息（role 换算成 UI 侧口径：`assistant` → `ai`）。
  ///
  /// 回放气泡**没有 `blocked`**：`Message` 上那组安全标记列从未被写入（真正的被拦记录
  /// 在 TutorLog，即 F-305 的「已拦截」徽标），所以历史消息上不会出现安全提示——
  /// 这是有意的不对称，别用「顺带补个字段」把它掩盖成看起来能用的空值。
  factory AssistantMessage.fromBubble(AssistantBubble bubble) => AssistantMessage(
        role: bubble.role == 'assistant' ? 'ai' : 'user',
        text: bubble.text,
        cards: bubble.cards.isEmpty ? null : bubble.cards,
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
  final AssistantRepository _repo;

  AssistantNotifier(this._repo) : super(const AssistantInitial());

  bool _submitting = false;

  /// 当前会话 id：首轮由后端 DONE 帧回写，之后每轮原样带回以续接上下文。
  ///
  /// 后端对该 id 做「parent_id + child_id」归属校验（`features/assistant/service.py`）：
  /// 不匹配时不报错，而是**另建会话并回写新 id**，这里随之覆盖（自愈，不会读到他人会话）。
  /// 只存内存——**有意如此**（产品决策 2026-09-16）：打开助手默认空态，不自动续接
  /// 历史会话；首轮发消息才新建会话。要接着上次聊就点「历史会话」里的对应行
  /// （resume 会接管该行的 session id，后续消息落回原会话）。
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
      await for (final ev in _repo.chat(
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

  /// 恢复一段历史会话（ADR-0048 的「我的对话」条目）：换掉当前会话身份与气泡，
  /// 之后的 [send] 会续接到它（后端按 session_id 归属校验后续接，零后端改动）。
  ///
  /// **只对家长自己的会话开放**：[AssistantConversation.isMine] 为 false 的（孩子的
  /// 会话）只能只读回放——家长发请求时 `child_id` 恒为 `None`，拿孩子的 session_id
  /// 续接必然过不了归属校验，后端会另建一段并回写新 id，屏幕上却像续上了。
  void resume({
    required String sessionId,
    required List<AssistantMessage> messages,
  }) {
    _currentSessionId = sessionId;
    state = AssistantActive(messages, false);
  }

  /// 开启新会话：丢弃当前 session_id 与气泡，下一轮重新在后端建立会话。
  ///
  /// 没有这一步 session_id 会一直续接，历史只增不减（后端仅截最近 20 条喂 prompt，
  /// 但会话本身不会结束）。入口是助手页历史模式顶栏的「新对话」（ADR-0048）——
  /// 它必须存在：有了「恢复续接」却没有「开新的一段」，用户就只能靠列表里多出
  /// 一堆碎会话。
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
        // 占位气泡带上阶段文案：路由/工具帧到达时把「思考中…」换成
        // 「已选择助手：X / 正在查询××」，用户能看到推进而不是干等。
        out.add(AssistantMessage(
          role: 'ai',
          thinking: true,
          stage: fold.stage,
        ));
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

final assistantNotifierProvider =
    StateNotifierProvider<AssistantNotifier, AssistantState>((ref) {
  final repo = ref.watch(assistantRepositoryProvider);
  return AssistantNotifier(repo);
});
