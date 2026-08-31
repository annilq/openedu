import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/data/remote/sse_client.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/exceptions/app_exception.dart';
import '../../../../shared/domain/providers/core_providers.dart';

// —— 家长端：生成任务 ——
sealed class TaskGenState {
  const TaskGenState();
}
class TaskGenIdle extends TaskGenState { const TaskGenIdle(); }
class TaskGenLoading extends TaskGenState { const TaskGenLoading(); }
class TaskGenSuccess extends TaskGenState {
  final TaskModel task;
  const TaskGenSuccess(this.task);
}
class TaskGenError extends TaskGenState {
  final String message;
  const TaskGenError(this.message);
}
class TaskGenPreview extends TaskGenState {
  final List<QuestionPreview> questions;
  final bool streaming;
  const TaskGenPreview(this.questions, {this.streaming = false});
}

class TaskGenNotifier extends StateNotifier<TaskGenState> {
  final NetworkService _network;
  TaskGenNotifier(this._network) : super(const TaskGenIdle());

  Future<void> generate({
    required String childId,
    required String title,
    required List<TaskSpecModel> specs,
    List<String>? focusInterest,
    String? model,
  }) async {
    state = const TaskGenLoading();
    try {
      final body = <String, dynamic>{
        'child_id': childId,
        'title': title,
        'specs': specs.map((s) => s.toJson()).toList(),
      };
      // 兴趣题模式（WF-4）：显式聚焦主题放请求顶层；缺省=后端自动轻融入画像。
      if (focusInterest != null) body['focus_interest'] = focusInterest;
      // 多模型（票据 08）：家长可选模型；null = 后端自动（默认/全局）。
      if (model != null) body['model'] = model;
      final data = await _network.post('/tasks/batch-generate', body: body);
      // R3：生成后保持 draft 态，把确认/派发动作交给草稿审核页。
      state = TaskGenSuccess(TaskModel.fromJson(data));
    } catch (e) {
      state = TaskGenError(e.toString());
    }
  }

  /// 流式预览出题（票据 08）：题卡逐张浮现，不落库。
  /// 完成后返回 [TaskGenPreview]，由 UI 展示题卡并提供「保存为任务」入口
  /// （保存走 [generate]，复用原有草稿审核流）。事件处理对齐后端 SSE 信封。
  Future<void> preview({
    required String childId,
    required String title,
    required List<TaskSpecModel> specs,
    List<String>? focusInterest,
    String? model,
  }) async {
    final body = <String, dynamic>{
      'child_id': childId,
      'title': title,
      'specs': specs.map((s) => s.toJson()).toList(),
    };
    if (focusInterest != null) body['focus_interest'] = focusInterest;
    if (model != null) body['model'] = model;

    final questions = <QuestionPreview>[];
    state = const TaskGenPreview([], streaming: true);
    try {
      streamLoop:
      await for (final ev
          in SseClient(_network).stream('/stream/tasks/generate', body: body)) {
        switch (ev.event) {
          case 'question':
            questions.add(QuestionPreview.fromJson(ev.data));
            state = TaskGenPreview(List.from(questions), streaming: true);
          case 'safety_refusal':
            final msg = ev.data['reason'] as String? ?? '内容安全拦截';
            state = TaskGenError('🛡️ $msg');
            break streamLoop;
          case 'error':
            final msg = ev.data['message'] as String? ?? '出错了，请稍后再试';
            state = TaskGenError('⚠️ $msg');
            break streamLoop;
          case 'done':
            state = TaskGenPreview(List.from(questions), streaming: false);
            break streamLoop;
        }
      }
    } on AppException catch (e) {
      state = TaskGenError('⏳ ${e.message}');
    } catch (e) {
      state = TaskGenError('⚠️ 网络异常，请稍后重试');
    }
  }

  void reset() => state = const TaskGenIdle();
}

final taskGenNotifierProvider =
    StateNotifierProvider<TaskGenNotifier, TaskGenState>((ref) {
  final network = ref.watch(networkServiceProvider);
  return TaskGenNotifier(network);
});

// —— 娃娃端：今日任务 ——
sealed class TodayTasksState {
  const TodayTasksState();
}
class TodayTasksInitial extends TodayTasksState { const TodayTasksInitial(); }
class TodayTasksLoading extends TodayTasksState { const TodayTasksLoading(); }
class TodayTasksLoaded extends TodayTasksState {
  final List<TaskModel> tasks;
  const TodayTasksLoaded(this.tasks);
}
class TodayTasksError extends TodayTasksState {
  final String message;
  const TodayTasksError(this.message);
}

class TodayTasksNotifier extends StateNotifier<TodayTasksState> {
  final NetworkService _network;
  TodayTasksNotifier(this._network) : super(const TodayTasksInitial());

  Future<void> load() async {
    state = const TodayTasksLoading();
    try {
      final data = await _network.get('/tasks/today');
      final tasks = (data as List)
          .map((e) => TaskModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = TodayTasksLoaded(tasks);
    } catch (e) {
      state = TodayTasksError(e.toString());
    }
  }
}

final todayTasksNotifierProvider =
    StateNotifierProvider<TodayTasksNotifier, TodayTasksState>((ref) {
  final network = ref.watch(networkServiceProvider);
  return TodayTasksNotifier(network);
});

// —— 家长端：查看娃娃进度 ——
sealed class ProgressState {
  const ProgressState();
}
class ProgressInitial extends ProgressState { const ProgressInitial(); }
class ProgressLoading extends ProgressState { const ProgressLoading(); }
class ProgressLoaded extends ProgressState {
  final ProgressModel progress;
  const ProgressLoaded(this.progress);
}
class ProgressError extends ProgressState {
  final String message;
  const ProgressError(this.message);
}

class ProgressNotifier extends StateNotifier<ProgressState> {
  final NetworkService _network;
  ProgressNotifier(this._network) : super(const ProgressInitial());

  Future<void> load(String childId) async {
    state = const ProgressLoading();
    try {
      final data = await _network.get('/tasks/children/$childId/progress');
      state = ProgressLoaded(ProgressModel.fromJson(data));
    } catch (e) {
      state = ProgressError(e.toString());
    }
  }
}

final progressNotifierProvider =
    StateNotifierProvider<ProgressNotifier, ProgressState>((ref) {
  final network = ref.watch(networkServiceProvider);
  return ProgressNotifier(network);
});

// —— 家长端：知识点掌握度看板 ——
sealed class MasteryState {
  const MasteryState();
}
class MasteryInitial extends MasteryState { const MasteryInitial(); }
class MasteryLoading extends MasteryState { const MasteryLoading(); }
class MasteryLoaded extends MasteryState {
  final MasteryModel mastery;
  const MasteryLoaded(this.mastery);
}
class MasteryError extends MasteryState {
  final String message;
  const MasteryError(this.message);
}

class MasteryNotifier extends StateNotifier<MasteryState> {
  final NetworkService _network;
  MasteryNotifier(this._network) : super(const MasteryInitial());

  Future<void> load(String childId) async {
    state = const MasteryLoading();
    try {
      final data = await _network.get('/tasks/children/$childId/mastery');
      state = MasteryLoaded(MasteryModel.fromJson(data));
    } catch (e) {
      state = MasteryError(e.toString());
    }
  }
}

final masteryNotifierProvider =
    StateNotifierProvider<MasteryNotifier, MasteryState>((ref) {
  final network = ref.watch(networkServiceProvider);
  return MasteryNotifier(network);
});
