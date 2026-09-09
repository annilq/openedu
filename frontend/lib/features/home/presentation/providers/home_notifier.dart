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
    // 当前正在生成的题序号（-1 = 无）。STEP 帧到达时置为下一题序号，题卡 DATA 帧
    // 到达后归 -1（内联区折叠，推理随卡落到题卡的 info icon）。
    var liveIndex = -1;
    // 0 题兜底文案：捕获后端 ASSISTANT_MESSAGE（出题 subagent count=0 时下发
    // 「本次未能生成题目，请调整科目或年级后重试。」），流结束 0 题时回显。
    var lastMessage = '';
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
          case AssistantEventType.step:
            // 新题开始：展开内联区（序号 = 下一题），清空上一题残留的推理文本。
            liveIndex = questions.length;
            liveLabel = ev.label ?? '生成中';
            liveReasoning = '';
          case AssistantEventType.thinking:
            // 路由帧（extra.business / extra.routing）跳过：那是「正在选择助手…」
            // 这类编排状态，不是出题思路，拼进推理区会污染展示。
            final extra = ev.extra;
            final isRouting = extra != null &&
                (extra['business'] != null || extra['routing'] == true);
            if (!isRouting) {
              liveReasoning += ev.text ?? '';
            }
          case AssistantEventType.assistantMessage:
            // 出题 subagent 在 0 题时会下发「本次未能生成题目…」说明。
            if (ev.text != null && ev.text!.isNotEmpty) lastMessage = ev.text!;
          case AssistantEventType.data:
            final type = ev.data?['type'];
            if (type == 'question' && ev.data?['result'] is Map) {
              questions.add(
                QuestionPreview.fromJson(
                  ev.data!['result'] as Map<String, dynamic>,
                ),
              );
              // 题卡到达：折叠内联区（推理已随卡落到 info icon）。
              liveIndex = -1;
              liveLabel = '';
              liveReasoning = '';
            }
          case AssistantEventType.toolResult:
            liveIndex = -1;
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
          liveIndex: liveIndex,
          liveLabel: liveLabel,
          liveReasoning: liveReasoning,
        );
      }
      // UX 修正：流结束若 0 题，直接回显后端说明并跳过必败的落库请求，
      // 避免误触发后端 TASK_EMPTY_SPECS「请先生成题目再保存」。
      if (questions.isEmpty) {
        state = TaskGenError(
          lastMessage.isNotEmpty
              ? lastMessage
              : '本次未能生成题目，请调整科目或年级后重试。',
        );
        return;
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
