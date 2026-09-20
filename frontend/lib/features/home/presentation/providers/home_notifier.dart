import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/presentation/resource.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/exceptions/app_exception.dart';
import '../../../assistant/domain/assistant_requests.dart';
import '../../../assistant/domain/question_gen_fold.dart';
import '../../../assistant/domain/repositories/assistant_repository.dart';
import '../../../assistant/providers/assistant_provider.dart';
import '../../domain/repositories/tasks_repository.dart';
import '../../providers/home_provider.dart';

// —— 家长端：生成任务 ——
sealed class TaskGenState {
  const TaskGenState();
}
class TaskGenIdle extends TaskGenState { const TaskGenIdle(); }
class TaskGenLoading extends TaskGenState { const TaskGenLoading(); }
class TaskGenSuccess extends TaskGenState {
  final TaskModel task;

  /// 应出题数（各条规格 count 之和）；0 表示未知（不校验少题）。
  final int expected;

  /// 单题失败原因（按发生顺序）；非空表示本次有题没生成出来。
  final List<String> failures;

  const TaskGenSuccess(this.task, {this.expected = 0, this.failures = const []});

  /// 本次是否少题：应出题数已知且落库题数不足。
  bool get isShort => expected > 0 && task.questions.length < expected;

  /// 少题提示文案（供 UI 直接展示）。
  ///
  /// 少题的补齐手段在草稿页是**单题换一题**——整卷重生成已移除（ADR-0056），
  /// 它等价于「整份推翻重来」，与闸门处的「重新生成」重复且要全量重跑。
  String get shortMessage => failures.isNotEmpty
      ? '应出 $expected 题，实际只生成 ${task.questions.length} 题：${failures.first}。'
          '可在草稿页逐题「换一题」补齐。'
      : '应出 $expected 题，实际只生成 ${task.questions.length} 题，可在草稿页逐题「换一题」补齐。';
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

  /// 单题失败原因（STEP status == 'error'），非空表示本次有题没生成出来。
  final List<String> failures;

  /// 首题 STEP 到达前的阶段文案（路由/工具帧提取）：连接 + 预检 + 首题 TTFT
  /// 这段死窗里，加载区用它替代裸转圈。空串 = 尚无阶段帧，用默认文案。
  final String stage;

  const TaskGenPreview(
    this.questions, {
    this.streaming = false,
    this.liveIndex = -1,
    this.liveLabel = '',
    this.liveReasoning = '',
    this.failures = const [],
    this.stage = '',
  });
}

/// 待确认的预览批次：题卡 + 落库请求体 + 少题元信息。纯内存，随 [TaskGenReady] 一起存在。
class _Pending {
  final Map<String, dynamic> body;
  final List<QuestionPreview> questions;
  final int expected;
  final List<String> failures;

  const _Pending({
    required this.body,
    required this.questions,
    required this.expected,
    required this.failures,
  });
}

/// 生成结束、**尚未落库**，停在生成页等家长确认（ADR-0056 审阅闸门）。
///
/// 这一态的存在意义是「落库时机后移」：题卡只在内存里，数据库里没有任何行。
/// 因此此态下家长可以安全地「重新生成」（不会留下第二份草稿）或「放弃」
/// （不需要调任何删除接口）。确认后才 [TaskGenNotifier.confirm] 落库为 draft。
class TaskGenReady extends TaskGenState {
  final List<QuestionPreview> questions;

  /// 应出题数；0 表示未知。
  final int expected;

  /// 单题失败原因；非空表示本次有题没生成出来。
  final List<String> failures;

  const TaskGenReady(
    this.questions, {
    this.expected = 0,
    this.failures = const [],
  });

  /// 本次是否少题：确认前就告知，别等落库后才发现残缺。
  bool get isShort => expected > 0 && questions.length < expected;
}

class TaskGenNotifier extends StateNotifier<TaskGenState> {
  final TasksRepository _tasks;
  final AssistantRepository _assistant;

  /// 待确认的一批预览题（ADR-0056）：非空即处于 [TaskGenReady]，
  /// 确认后清空。**纯内存，不落库**——这是「放弃无需删除」的前提。
  _Pending? _pending;

  TaskGenNotifier(this._tasks, this._assistant) : super(const TaskGenIdle());

  /// 把结构化 specs 经 `/tasks/generate` 直传后端（ADR-0034 P1）：服务端据此构造
  /// 出题 prompt 并走 question subagent 流式返回题卡，不再拼自然语言走 /assistant/chat。
  Future<void> generate({
    required String childId,
    required String title,
    required List<TaskSpecModel> specs,
    List<String>? focusInterest,
    String? model,
  }) async {
    // 结构化 specs → /tasks/generate（服务端构造 prompt，AG-UI 事件协议，ADR-0025）；
    // 流结束后再把题卡落库为草稿任务。事件解释委托 [QuestionGenFold]（纯模块）：
    // 本 notifier 只负责喂事件、落状态与落库，逐帧规则全部收敛到那个模块并可单测。
    var fold = const QuestionGenFold();
    // 应出题数：各条规格 count 之和。流结束后据此校验「少题」——逐题串行出题时
    // 单题失败只会丢一条 STEP(status=error)，不做校验就会静默落库残缺任务。
    final expected = specs.fold<int>(0, (sum, s) => sum + s.count);
    state = TaskGenPreview(fold.questions, streaming: true);
    try {
      final stream = _assistant.generate(
        TaskGenerateReq(
          specs: specs,
          model: model,
          focusInterest: focusInterest,
          childId: childId,
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
          failures: fold.failures,
          stage: fold.stage,
        );
      }
      // UX 修正：流结束若 0 题，直接回显后端说明并跳过必败的落库请求，
      // 避免误触发后端 TASK_EMPTY_SPECS「请先生成题目再保存」。
      if (fold.questions.isEmpty) {
        state = TaskGenError(fold.emptyMessage);
        return;
      }
      // 审阅闸门（ADR-0056）：**流结束不落库**，只把题卡与请求体留在内存里等确认。
      // 后果有三：① 重新生成不会产出第二份 draft；② 放弃无需任何删除调用；
      // ③ 后端少一次必然发生的聚合写入——被放弃的生成在库里不留痕迹。
      _pending = _Pending(
        body: _buildBody(
          childId: childId,
          title: title,
          specs: specs,
          focusInterest: focusInterest,
          model: model,
        ),
        questions: fold.questions,
        expected: expected,
        failures: fold.failures,
      );
      state = TaskGenReady(
        fold.questions,
        expected: expected,
        failures: fold.failures,
      );
    } on AppException catch (e) {
      state = TaskGenError(e.message);
    } catch (e) {
      state = TaskGenError('⚠️ 网络异常，请稍后重试');
    }
  }

  /// 确认并落库：把预览题卡 POST 到 /tasks/from-generated 落库为 draft 任务。
  ///
  /// 这是 [TaskGenReady] 之后的唯一出口。此前不存在任何数据库行，
  /// 故此调用失败时家长仍停留在生成页，题卡未丢，可重试。
  Future<void> confirm() async {
    final pending = _pending;
    if (pending == null) return;
    await _persist(
      pending.questions,
      pending.body,
      expected: pending.expected,
      failures: pending.failures,
    );
  }

  /// 放弃这批预览题：预览纯内存，无需任何删除调用，直接回空闲态。
  void discard() {
    _pending = null;
    state = const TaskGenIdle();
  }

  /// 把已生成题卡 POST 到 /tasks/from-generated 落库为 draft 任务。
  Future<void> _persist(
    List<QuestionPreview> questions,
    Map<String, dynamic> body, {
    int expected = 0,
    List<String> failures = const [],
  }) async {
    // 必填项 questions：把已流式题卡（QuestionPreview.toJson，snake_case）注入请求体。
    // 之前 generate() 漏了这一步 → 后端 422（TaskFromGenerated.questions 必填）。
    body['questions'] = questions.map((q) => q.toJson()).toList();
    // 落库期间保持流式态：隐藏生成/预览按钮，题卡继续展示（带保存中提示）。
    state = TaskGenPreview(List.from(questions), streaming: true, failures: failures);
    try {
      final task = await _tasks.persistGenerated(body);
      // R3：生成后保持 draft 态，把确认/派发动作交给草稿审核页。
      // 少题信息一并返回：草稿照常落库（不浪费已生成的题），由 UI 醒目提示家长补齐。
      state = TaskGenSuccess(
        task,
        expected: expected,
        failures: failures,
      );
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

  /// 回到空闲态。确认成功后由 UI 调用，同时丢弃待确认批次（已落库，不再需要）。
  void reset() {
    _pending = null;
    state = const TaskGenIdle();
  }
}

final taskGenNotifierProvider =
    StateNotifierProvider<TaskGenNotifier, TaskGenState>((ref) {
  return TaskGenNotifier(
    ref.watch(tasksRepositoryProvider),
    ref.watch(assistantRepositoryProvider),
  );
});

// —— 娃娃端：今日任务 ——（GET /tasks/today，纯资源加载）
final todayTasksNotifierProvider =
    StateNotifierProvider<ResourceNotifier<List<TaskModel>>, Resource<List<TaskModel>>>(
  (ref) => ResourceNotifier(
    () => ref.watch(tasksRepositoryProvider).todayTasks(),
  ),
);

// —— 家长端：查看娃娃进度 ——（路径依赖 childId）
final progressNotifierProvider = StateNotifierProvider<
    ParamResourceNotifier<ProgressModel, String>, Resource<ProgressModel>>(
  (ref) => ParamResourceNotifier(
    (childId) => ref.watch(tasksRepositoryProvider).progress(childId),
  ),
);

// —— 家长端：知识点掌握度看板 ——（路径依赖 childId）
final masteryNotifierProvider = StateNotifierProvider<
    ParamResourceNotifier<MasteryModel, String>, Resource<MasteryModel>>(
  (ref) => ParamResourceNotifier(
    (childId) => ref.watch(tasksRepositoryProvider).mastery(childId),
  ),
);
