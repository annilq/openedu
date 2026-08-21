import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../../../shared/exceptions/app_exception.dart';

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
  final NetworkService _network;
  bool _submitting = false;

  TutorNotifier(this._network) : super(const TutorInitial());

  /// 防重入：提交中忽略重复点击，避免连点重复消耗每日额度。
  Future<void> ask(TutorAskReq req) async {
    if (_submitting) return;
    _submitting = true;

    // 立即把娃娃的问题气泡加进去，给出即时反馈
    // 注：TutorLoading 分支在防重入下实际不可达（Loading 期间 _submitting 恒 true，
    // 第二次 ask 直接返回），保留作防御；历史列表从两态均可提取。
    final history = switch (state) {
      TutorLoaded(:final messages) || TutorLoading(:final messages) =>
        List<TutorMessage>.from(messages),
      _ => <TutorMessage>[],
    };
    state = TutorLoading([
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

// —— 家长端：AI 使用管控（T10，故事 23/26） ——
sealed class TutorQuotaState {
  const TutorQuotaState();
}

class TutorQuotaInitial extends TutorQuotaState {
  const TutorQuotaInitial();
}

class TutorQuotaLoading extends TutorQuotaState {
  const TutorQuotaLoading();
}

class TutorQuotaLoaded extends TutorQuotaState {
  final TutorQuotaModel quota;
  const TutorQuotaLoaded(this.quota);
}

class TutorQuotaError extends TutorQuotaState {
  final String message;
  const TutorQuotaError(this.message);
}

class TutorQuotaNotifier extends StateNotifier<TutorQuotaState> {
  final NetworkService _network;
  TutorQuotaNotifier(this._network) : super(const TutorQuotaInitial());

  Future<void> load({required String childId}) async {
    state = const TutorQuotaLoading();
    try {
      final data = await _network.get(
        '/tutor/quota',
        query: {'child_id': childId},
      );
      state = TutorQuotaLoaded(
        TutorQuotaModel.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      state = TutorQuotaError(e.toString());
    }
  }

  /// 整体覆盖式保存；成功后回到 Loaded。
  Future<String?> save({
    required String childId,
    required TutorQuotaUpdateReq req,
  }) async {
    try {
      final data = await _network.put(
        '/tutor/quota',
        query: {'child_id': childId},
        body: req.toJson(),
      );
      state = TutorQuotaLoaded(
        TutorQuotaModel.fromJson(data as Map<String, dynamic>),
      );
      return null; // 无错误
    } on AppException catch (e) {
      return e.message;
    } catch (e) {
      return '保存失败，请稍后重试';
    }
  }
}

/// family 按 childId 隔离：两娃切换时不会互串配置。
final tutorQuotaNotifierProvider = StateNotifierProvider.family<
    TutorQuotaNotifier, TutorQuotaState, String>((ref, childId) {
  final network = ref.watch(networkServiceProvider);
  return TutorQuotaNotifier(network);
});

// —— 家长端：当日用量 ——
sealed class TutorUsageState {
  const TutorUsageState();
}

class TutorUsageInitial extends TutorUsageState {
  const TutorUsageInitial();
}

class TutorUsageLoading extends TutorUsageState {
  const TutorUsageLoading();
}

class TutorUsageLoaded extends TutorUsageState {
  final TutorUsageModel usage;
  const TutorUsageLoaded(this.usage);
}

class TutorUsageError extends TutorUsageState {
  final String message;
  const TutorUsageError(this.message);
}

class TutorUsageNotifier extends StateNotifier<TutorUsageState> {
  final NetworkService _network;
  TutorUsageNotifier(this._network) : super(const TutorUsageInitial());

  Future<void> load({required String childId}) async {
    state = const TutorUsageLoading();
    try {
      final data = await _network.get(
        '/tutor/usage',
        query: {'child_id': childId},
      );
      state = TutorUsageLoaded(
        TutorUsageModel.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      state = TutorUsageError(e.toString());
    }
  }
}

final tutorUsageNotifierProvider = StateNotifierProvider.family<
    TutorUsageNotifier, TutorUsageState, String>((ref, childId) {
  final network = ref.watch(networkServiceProvider);
  return TutorUsageNotifier(network);
});
