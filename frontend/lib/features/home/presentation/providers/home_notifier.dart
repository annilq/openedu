import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/presentation/resource.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../../../shared/exceptions/app_exception.dart';
import '../../../assistant/data/assistant_api_client.dart';
import '../../../assistant/domain/question_gen_fold.dart';
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
    // 方案 A：结构化 specs → 自然语言 prompt，走统一 /assistant/chat 的 question
    // subagent（AG-UI 事件协议，ADR-0025）；流结束后再把题卡落库为草稿任务。
    // 事件解释委托 [QuestionGenFold]（纯模块）：本 notifier 只负责喂事件、落状态
    // 与落库，逐帧规则全部收敛到那个模块并可单测。
    var fold = const QuestionGenFold();
    state = TaskGenPreview(fold.questions, streaming: true);
    try {
      final stream = _assistant.streamChat(
        AssistantChatReq(
          message: _buildPrompt(specs),
          model: model,
          focusInterest: focusInterest,
        ),
      );
      await for (final ev in stream) {
        fold = fold.apply(ev);
        if (fold.hasError) {
          state = TaskGenError(fold.errorText!);
          return;
        }
        state = TaskGenPreview(
          fold.questions,
          streaming: true,
          liveIndex: fold.liveIndex,
          liveLabel: fold.liveLabel,
          liveReasoning: fold.liveReasoning,
        );
      }
      // UX 修正：流结束若 0 题，直接回显后端说明并跳过必败的落库请求，
      // 避免误触发后端 TASK_EMPTY_SPECS「请先生成题目再保存」。
      if (fold.questions.isEmpty) {
        state = TaskGenError(fold.emptyMessage);
        return;
      }
      await _persist(
        fold.questions,
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

// —— 娃娃端：今日任务 ——（GET /tasks/today，纯资源加载）
final todayTasksNotifierProvider =
    StateNotifierProvider<ResourceNotifier<List<TaskModel>>, Resource<List<TaskModel>>>(
  (ref) => ResourceNotifier(
    ref.watch(networkServiceProvider),
    path: '/tasks/today',
    parse: (d) => decodeList(d, TaskModel.fromJson),
  ),
);

// —— 家长端：查看娃娃进度 ——（路径依赖 childId）
final progressNotifierProvider = StateNotifierProvider<
    ParamResourceNotifier<ProgressModel, String>, Resource<ProgressModel>>(
  (ref) => ParamResourceNotifier(
    ref.watch(networkServiceProvider),
    pathOf: (childId) => '/tasks/children/$childId/progress',
    parse: (d) => ProgressModel.fromJson(decodeMap(d)),
  ),
);

// —— 家长端：知识点掌握度看板 ——（路径依赖 childId）
final masteryNotifierProvider = StateNotifierProvider<
    ParamResourceNotifier<MasteryModel, String>, Resource<MasteryModel>>(
  (ref) => ParamResourceNotifier(
    ref.watch(networkServiceProvider),
    pathOf: (childId) => '/tasks/children/$childId/mastery',
    parse: (d) => MasteryModel.fromJson(decodeMap(d)),
  ),
);
