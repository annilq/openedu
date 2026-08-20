import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';

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

class TutorLoaded extends TutorState {
  final List<TutorMessage> messages;
  const TutorLoaded(this.messages);
}

class TutorNotifier extends StateNotifier<TutorState> {
  final NetworkService _network;
  bool _submitting = false;

  TutorNotifier(this._network) : super(const TutorInitial());

  /// 防重入：提交中忽略重复点击，避免连点重复消耗每日额度。
  Future<void> ask(TutorAskReq req) async {
    if (_submitting) return;
    _submitting = true;

    // 立即把娃娃的问题气泡加进去，给出即时反馈
    final history = state is TutorLoaded
        ? List<TutorMessage>.from((state as TutorLoaded).messages)
        : <TutorMessage>[];
    state = TutorLoaded([
      ...history,
      TutorMessage(role: 'child', text: req.question),
    ]);

    try {
      final data = await _network.post('/tutor/ask', body: req.toJson());
      final ans = TutorAnswer.fromJson(data as Map<String, dynamic>);
      state = TutorLoaded([
        ...history,
        TutorMessage(role: 'child', text: req.question),
        TutorMessage(role: 'ai', text: ans.answer, blocked: ans.blocked),
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
  final network = ref.watch(networkServiceProvider);
  return TutorNotifier(network);
});

// —— 家长端：AI 答疑日志 ——
sealed class TutorLogsState {
  const TutorLogsState();
}

class TutorLogsInitial extends TutorLogsState {
  const TutorLogsInitial();
}

class TutorLogsLoading extends TutorLogsState {
  const TutorLogsLoading();
}

class TutorLogsLoaded extends TutorLogsState {
  final List<TutorLogModel> logs;
  const TutorLogsLoaded(this.logs);
}

class TutorLogsError extends TutorLogsState {
  final String message;
  const TutorLogsError(this.message);
}

class TutorLogsNotifier extends StateNotifier<TutorLogsState> {
  final NetworkService _network;
  TutorLogsNotifier(this._network) : super(const TutorLogsInitial());

  Future<void> load({required String childId}) async {
    state = const TutorLogsLoading();
    try {
      final data = await _network.get(
        '/tutor/logs',
        query: {'child_id': childId},
      );
      final logs = (data as List)
          .map((e) => TutorLogModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = TutorLogsLoaded(logs);
    } catch (e) {
      state = TutorLogsError(e.toString());
    }
  }
}

final tutorLogsNotifierProvider =
    StateNotifierProvider<TutorLogsNotifier, TutorLogsState>((ref) {
  final network = ref.watch(networkServiceProvider);
  return TutorLogsNotifier(network);
});
