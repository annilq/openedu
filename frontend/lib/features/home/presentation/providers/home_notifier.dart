import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genkit/client.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/data/remote/genkit_ai_client.dart';
import '../../../../shared/domain/models/models.dart';
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
  /// 生成中（内联推理区）状态：当前正在出的题序号（-1 表示无）；其进度标签与已累积的
  /// 出题推理文本。某题 CARD 到达后该内联区折叠（liveIndex 归 -1），推理随卡落下供
  /// 卡片右上角 info icon 展开（ADR-0017）。
  final int liveIndex;
  final String liveLabel;
  final String liveReasoning;

  const TaskGenPreview(
    this.questions, {
    this.streaming = false,
    this.liveIndex = -1,
    this.liveLabel = '',
    this.liveReasoning = '',
  });
}

class TaskGenNotifier extends StateNotifier<TaskGenState> {
  final NetworkService _network;
  final GenkitAiClient _genkit;
  TaskGenNotifier(this._network, this._genkit) : super(const TaskGenIdle());

  Future<void> generate({
    required String childId,
    required String title,
    required List<TaskSpecModel> specs,
    List<String>? focusInterest,
    String? model,
  }) async {
    final body = _buildBody(
      childId: childId,
      title: title,
      specs: specs,
      focusInterest: focusInterest,
      model: model,
    );
    final questions = <QuestionPreview>[];
    var liveIndex = -1;
    var liveLabel = '';
    var liveReasoning = '';
    // 流式渲染：先连 /ai/tasks/generate 逐题产出信封 chunk（ADR-0017：
    // STEP → REASONING → CARD），流结束后再把已生成题卡落库为草稿任务。
    state = const TaskGenPreview([], streaming: true);
    try {
      final stream = _genkit.streamTasks(body);
      await for (final chunk in stream) {
        if (chunk is StepChunk) {
          liveIndex = chunk.qIndex;
          liveLabel = chunk.label;
          liveReasoning = '';
        } else if (chunk is ReasoningChunk) {
          liveReasoning += chunk.delta;
        } else if (chunk is CardChunk) {
          questions.add(chunk.question);
          liveIndex = -1;
          liveLabel = '';
          liveReasoning = '';
        }
        state = TaskGenPreview(
          List.from(questions),
          streaming: true,
          liveIndex: liveIndex,
          liveLabel: liveLabel,
          liveReasoning: liveReasoning,
        );
      }
      await stream.onResult; // 确认流已结束（末帧 result）
      await _persist(questions, body);
    } on GenkitException catch (e) {
      state = TaskGenError(friendlyGenkitError(e));
    } catch (e) {
      state = TaskGenError('⚠️ 网络异常，请稍后重试');
    }
  }

  /// 预览后的「保存为任务」：直接落库已流式返回的题卡（不再二次生成）。
  Future<void> savePreview({
    required String childId,
    required String title,
    required List<TaskSpecModel> specs,
    required List<QuestionPreview> questions,
    List<String>? focusInterest,
    String? model,
  }) async {
    if (questions.isEmpty) {
      state = const TaskGenError('暂无可保存的题目');
      return;
    }
    final body = _buildBody(
      childId: childId,
      title: title,
      specs: specs,
      focusInterest: focusInterest,
      model: model,
    );
    // questions 由 _persist 统一注入落库请求体。
    await _persist(questions, body);
  }

  /// 把已生成题卡 POST 到 /tasks/from-generated 落库为 draft 任务。
  Future<void> _persist(
    List<QuestionPreview> questions,
    Map<String, dynamic> body,
  ) async {
    // 必填项 questions：把已流式题卡（QuestionPreview.toJson，snake_case）注入请求体。
    // 之前 generate() 漏了这一步 → 后端 422（TaskFromGenerated.questions 必填）。
    body['questions'] = questions.map((q) => q.toJson()).toList();
    // 落库期间保持流式态：隐藏生成/预览按钮，题卡继续展示（带保存中提示）。
    state = TaskGenPreview(List.from(questions), streaming: true);
    try {
      final data = await _network.post('/tasks/from-generated', body: body);
      // R3：生成后保持 draft 态，把确认/派发动作交给草稿审核页。
      state = TaskGenSuccess(TaskModel.fromJson(data));
    } on GenkitException catch (e) {
      state = TaskGenError(friendlyGenkitError(e));
    } catch (e) {
      state = TaskGenError('⚠️ 保存失败，请稍后重试');
    }
  }

  Map<String, dynamic> _buildBody({
    required String childId,
    required String title,
    required List<TaskSpecModel> specs,
    List<String>? focusInterest,
    String? model,
  }) {
    final body = <String, dynamic>{
      'child_id': childId,
      'title': title,
      'specs': specs.map((s) => s.toJson()).toList(),
    };
    // 兴趣题模式（WF-4）：显式聚焦主题放请求顶层；缺省=后端自动轻融入画像。
    if (focusInterest != null) body['focus_interest'] = focusInterest;
    // 多模型（票据 08）：家长可选模型；null = 后端自动（默认/全局）。
    if (model != null) body['model'] = model;
    return body;
  }

  /// 流式预览出题（Genkit 全栈，ADR-0015）：直连后端 `/ai/tasks/generate` 原生
  /// action 端点，题卡逐张浮现（每帧一道 [QuestionPreview]），不落库；
  /// 路由层（归属校验 / 输入安全 / 配额）非 2xx 以 [GenkitException] 抛出。
  /// 完成后返回 [TaskGenPreview]，由 UI 展示题卡并提供「保存为任务」入口
  /// （保存走 [generate]，复用原有草稿审核流）。
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
    var liveIndex = -1;
    var liveLabel = '';
    var liveReasoning = '';
    state = const TaskGenPreview([], streaming: true);
    try {
      final stream = _genkit.streamTasks(body);
      await for (final chunk in stream) {
        if (chunk is StepChunk) {
          liveIndex = chunk.qIndex;
          liveLabel = chunk.label;
          liveReasoning = '';
        } else if (chunk is ReasoningChunk) {
          liveReasoning += chunk.delta;
        } else if (chunk is CardChunk) {
          questions.add(chunk.question);
          liveIndex = -1;
          liveLabel = '';
          liveReasoning = '';
        }
        state = TaskGenPreview(
          List.from(questions),
          streaming: true,
          liveIndex: liveIndex,
          liveLabel: liveLabel,
          liveReasoning: liveReasoning,
        );
      }
      final result = await stream.onResult;
      state = TaskGenPreview(result, streaming: false);
    } on GenkitException catch (e) {
      state = TaskGenError(friendlyGenkitError(e));
    } catch (e) {
      state = TaskGenError('⚠️ 网络异常，请稍后重试');
    }
  }

  void reset() => state = const TaskGenIdle();
}

final taskGenNotifierProvider =
    StateNotifierProvider<TaskGenNotifier, TaskGenState>((ref) {
  final network = ref.watch(networkServiceProvider);
  final genkit = ref.watch(genkitAiClientProvider);
  return TaskGenNotifier(network, genkit);
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
