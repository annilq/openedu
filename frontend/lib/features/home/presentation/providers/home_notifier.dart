import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../../../shared/exceptions/app_exception.dart';
import '../../../assistant/data/assistant_api_client.dart';
import '../../../assistant/domain/assistant_event.dart';
import '../../../assistant/presentation/provider/assistant_notifier.dart';

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
  final AssistantApiClient _assistant;
  TaskGenNotifier(this._network, this._assistant) : super(const TaskGenIdle());

  /// 把结构化 specs 拼为自然语言 prompt（方案 A）：交后端 question subagent 解析。
  /// 用「，关于{知识点}」句式，使其自由文本解析能捕获 knowledge_point。
  String _buildPrompt(List<TaskSpecModel> specs) {
    const qtypeLabel = {
      'choice': '选择题',
      'fill': '填空题',
      'calc': '计算题',
      'open': '问答题',
    };
    final parts = specs.map((s) {
      final label = qtypeLabel[s.qtype] ?? '题';
      final kp = s.knowledgePoint.isNotEmpty ? '，关于${s.knowledgePoint}' : '';
      return '${s.grade}年级${s.subject}$label${s.count}道$kp';
    }).toList();
    return '帮我出${parts.join('、')}';
  }

  Future<void> generate({
    required String childId,
    required String title,
    required List<TaskSpecModel> specs,
    List<String>? focusInterest,
    String? model,
  }) async {
    final questions = <QuestionPreview>[];
    var liveLabel = '';
    var liveReasoning = '';
    // 方案 A：结构化 specs → 自然语言 prompt，走统一 /assistant/chat 的 question
    // subagent（AG-UI 事件协议，ADR-0025）；流结束后再把题卡落库为草稿任务。
    state = const TaskGenPreview([], streaming: true);
    try {
      final stream = _assistant.streamChat(
        AssistantChatReq(
          message: _buildPrompt(specs),
          model: model,
          focusInterest: focusInterest,
        ),
      );
      await for (final ev in stream) {
        switch (ev.eventType) {
          case AssistantEventType.toolCall:
            liveLabel = ev.label ?? '生成中';
          case AssistantEventType.thinking:
            // 路由帧（extra.business）跳过；其它推理增量累加为内联推理。
            if (ev.extra == null || ev.extra!['business'] == null) {
              liveReasoning += ev.text ?? '';
            }
          case AssistantEventType.data:
            final type = ev.data?['type'];
            if (type == 'question' && ev.data?['result'] is Map) {
              questions.add(
                QuestionPreview.fromJson(
                  ev.data!['result'] as Map<String, dynamic>,
                ),
              );
              liveLabel = '';
            }
          case AssistantEventType.toolResult:
            liveLabel = '';
          case AssistantEventType.error:
            state = TaskGenError(ev.message ?? '生成失败');
            return;
          case AssistantEventType.done:
            break;
        }
        state = TaskGenPreview(
          List.from(questions),
          streaming: true,
          liveLabel: liveLabel,
          liveReasoning: liveReasoning,
        );
      }
      await _persist(
        questions,
        _buildBody(
          childId: childId,
          title: title,
          specs: specs,
          focusInterest: focusInterest,
          model: model,
        ),
      );
    } on AppException catch (e) {
      state = TaskGenError(e.message);
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
    } on AppException catch (e) {
      state = TaskGenError(e.message);
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

  /// 流式预览出题（统一入口，ADR-0024）：经 [AssistantApiClient.streamChat] 走
  /// `/assistant/chat` 的 question subagent，题卡逐张浮现（DATA 事件携带
  /// [QuestionPreview]），不落库；路由层（归属校验 / 输入安全 / 配额）非 2xx 以
  /// [AppException] 抛出。
  Future<void> preview({
    required String childId,
    required String title,
    required List<TaskSpecModel> specs,
    List<String>? focusInterest,
    String? model,
  }) async {
    final questions = <QuestionPreview>[];
    var liveLabel = '';
    var liveReasoning = '';
    state = const TaskGenPreview([], streaming: true);
    try {
      final stream = _assistant.streamChat(
        AssistantChatReq(
          message: _buildPrompt(specs),
          model: model,
          focusInterest: focusInterest,
        ),
      );
      await for (final ev in stream) {
        switch (ev.eventType) {
          case AssistantEventType.toolCall:
            liveLabel = ev.label ?? '生成中';
          case AssistantEventType.thinking:
            if (ev.extra == null || ev.extra!['business'] == null) {
              liveReasoning += ev.text ?? '';
            }
          case AssistantEventType.data:
            final type = ev.data?['type'];
            if (type == 'question' && ev.data?['result'] is Map) {
              questions.add(
                QuestionPreview.fromJson(
                  ev.data!['result'] as Map<String, dynamic>,
                ),
              );
              liveLabel = '';
            }
          case AssistantEventType.toolResult:
            liveLabel = '';
          case AssistantEventType.error:
            state = TaskGenError(ev.message ?? '生成失败');
            return;
          case AssistantEventType.done:
            break;
        }
        state = TaskGenPreview(
          List.from(questions),
          streaming: true,
          liveLabel: liveLabel,
          liveReasoning: liveReasoning,
        );
      }
      state = TaskGenPreview(questions, streaming: false);
    } on AppException catch (e) {
      state = TaskGenError(e.message);
    } catch (e) {
      state = TaskGenError('⚠️ 网络异常，请稍后重试');
    }
  }

  void reset() => state = const TaskGenIdle();
}

final taskGenNotifierProvider =
    StateNotifierProvider<TaskGenNotifier, TaskGenState>((ref) {
  final network = ref.watch(networkServiceProvider);
  final assistant = ref.watch(assistantApiClientProvider);
  return TaskGenNotifier(network, assistant);
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
