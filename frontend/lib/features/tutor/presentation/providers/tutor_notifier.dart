import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../../../shared/presentation/resource.dart';
import '../../../../shared/exceptions/app_exception.dart';
import '../../../assistant/data/assistant_api_client.dart';
import '../../../assistant/domain/ai_text_fold.dart';
import '../../../assistant/presentation/provider/assistant_notifier.dart';

/// 一条对话气泡。
class TutorMessage {
  final String role; // child | ai
  final String text;
  final bool blocked; // 是否因安全原因返回了兜底

  const TutorMessage({
    required this.role,
    required this.text,
    this.blocked = false,
  });
}

// —— 娃娃端：AI 答疑对话 ——
sealed class TutorState {
  const TutorState();
}

class TutorInitial extends TutorState {
  const TutorInitial();
}

/// 请求进行中：保留已提交的气泡列表，等待 AI 回复。
class TutorLoading extends TutorState {
  final List<TutorMessage> messages;
  const TutorLoading(this.messages);
}

/// 请求完成：消息列表即当前对话（错误以气泡形式保留在列表里，见 ask()）。
class TutorLoaded extends TutorState {
  final List<TutorMessage> messages;
  const TutorLoaded(this.messages);
}

class TutorNotifier extends StateNotifier<TutorState> {
  final AssistantApiClient _assistant;
  bool _submitting = false;

  TutorNotifier(this._assistant) : super(const TutorInitial());

  /// 防重入：提交中忽略重复点击，避免连点重复消耗每日额度。
  Future<void> ask(TutorAskReq req) async {
    // 统一收敛到流式端点（SSE `/assistant/chat`），行为一致。
    return askStream(req);
  }

  /// 流式答疑（统一端点 `POST /assistant/chat`，ADR-0024）：
  /// 经 [AssistantApiClient.streamChat] 逐帧产出 AG-UI 事件，把
  /// `ASSISTANT_MESSAGE` 文本累加到 AI 气泡；路由层（鉴权 / 配额 / 输入安全）
  /// 的非 2xx 错误以 [AppException] 抛出，由上层文案透出。
  Future<void> askStream(TutorAskReq req) async {
    if (_submitting) return;
    _submitting = true;

    // 历史气泡 + 新娃娃问 + 占位 AI 气泡（流式填充）。
    final history = switch (state) {
      TutorLoaded(:final messages) || TutorLoading(:final messages) =>
        List<TutorMessage>.from(messages),
      _ => <TutorMessage>[],
    };
    state = TutorLoading([
      ...history,
      TutorMessage(role: 'child', text: req.question),
      const TutorMessage(role: 'ai', text: ''),
    ]);

    // 事件解释委托 [AiTextFold]（与悬浮助手共用同一份规则）：本 notifier 只负责
    // 喂事件与落状态，不再自己 switch eventType。
    var fold = const AiTextFold();
    try {
      final stream = _assistant.streamChat(
        AssistantChatReq(message: req.question),
      );
      await for (final ev in stream) {
        fold = fold.apply(ev);
        state = TutorLoading([
          ...history,
          TutorMessage(role: 'child', text: req.question),
          TutorMessage(role: 'ai', text: fold.text, blocked: fold.blocked),
        ]);
      }
      state = TutorLoaded([
        ...history,
        TutorMessage(role: 'child', text: req.question),
        TutorMessage(role: 'ai', text: fold.text, blocked: fold.blocked),
      ]);
    } on AppException catch (e) {
      // 服务端业务错误（含 429 次数/时长上限、403 学科范围）：透出提示文案
      state = TutorLoaded([
        ...history,
        TutorMessage(role: 'child', text: req.question),
        TutorMessage(role: 'ai', text: '⏳ ${e.message}'),
      ]);
    } catch (e) {
      // 出错也保留历史气泡，并附一条错误提示
      state = TutorLoaded([
        ...history,
        TutorMessage(role: 'child', text: req.question),
        const TutorMessage(role: 'ai', text: '⚠️ 网络异常，请稍后重试'),
      ]);
    } finally {
      _submitting = false;
    }
  }
}

final tutorNotifierProvider =
    StateNotifierProvider<TutorNotifier, TutorState>((ref) {
  final assistant = ref.watch(assistantApiClientProvider);
  return TutorNotifier(assistant);
});

// —— 家长端：AI 答疑日志 ——（GET /tutor/logs?child_id=）
final tutorLogsNotifierProvider = StateNotifierProvider<
    ParamResourceNotifier<List<TutorLogModel>, String>,
    Resource<List<TutorLogModel>>>(
  (ref) => ParamResourceNotifier(
    ref.watch(networkServiceProvider),
    pathOf: (_) => '/tutor/logs',
    queryOf: (childId) => {'child_id': childId},
    parse: (d) => decodeList(d, TutorLogModel.fromJson),
  ),
);

