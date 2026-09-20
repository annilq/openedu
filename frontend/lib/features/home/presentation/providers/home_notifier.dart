import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/presentation/resource.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/exceptions/app_exception.dart';
import '../../../assistant/domain/assistant_requests.dart';
import '../../../assistant/domain/question_gen_fold.dart';
import '../../../assistant/domain/repositories/assistant_repository.dart';
import '../../../assistant/providers/assistant_provider.dart';
import '../../domain/expected_question_count.dart';
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
  bool get isShort =>
      isUnderdelivered(expected: expected, actualCount: task.questions.length);

  /// 少题提示文案（供 UI 直接展示）。
  ///
  /// ⚠️ 出口只能指向真实存在的入口：草稿页没有「添加题目」、「换一题」也**不能加题**
  /// （ADR-0056 的硬约束：它只是维持题数不变地换掉一道题），整卷重生成同样已移除。
  /// 于是补齐的唯一路径是「回生成页重来一份」——此前这里指向一个不存在的按钮。
  String get shortMessage => failures.isNotEmpty
      ? '应出 $expected 题，实际只生成 ${task.questions.length} 题：${failures.first}。'
          '可回生成页重来一份。'
      : '应出 $expected 题，实际只生成 ${task.questions.length} 题，可回生成页重来一份。';
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

  /// 应出题数（各条规格 count 之和）；0 表示未知（不校验少题）。跨 Tab 的常驻指示条
  /// 用它显示「已出 N/M」进度，故预览态也带这个数字。
  final int expected;

  const TaskGenPreview(
    this.questions, {
    this.streaming = false,
    this.liveIndex = -1,
    this.liveLabel = '',
    this.liveReasoning = '',
    this.failures = const [],
    this.stage = '',
    this.expected = 0,
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

  /// 是否由家长主动停止（ADR-0057 Q1=B）：是则中性陈述「已停止 · 保留 N 题」，
  /// 不当成故障报警——自己按的停止不该被渲染成系统出错。
  final bool stopped;

  const TaskGenReady(
    this.questions, {
    this.expected = 0,
    this.failures = const [],
    this.stopped = false,
  });

  /// 本次是否少题：确认前就告知，别等落库后才发现残缺。
  bool get isShort =>
      isUnderdelivered(expected: expected, actualCount: questions.length);
}

class TaskGenNotifier extends StateNotifier<TaskGenState> {
  final TasksRepository _tasks;
  final AssistantRepository _assistant;

  /// 待确认的一批预览题（ADR-0056）：非空即处于 [TaskGenReady]，
  /// 确认后清空。**纯内存，不落库**——这是「放弃无需删除」的前提。
  _Pending? _pending;

  /// 出题过程中累计的折叠态（逐帧 apply 的纯模块）；[stop] 需要在循环外快照当前进度，
  /// 故提升为实例字段而非局部变量。
  QuestionGenFold _fold = const QuestionGenFold();

  /// 本次应出题数（各规格 count 之和），供 [stop] 在停止时原样带入待确认态。
  int _expected = 0;

  /// 主动停止标志：循环每帧开头检测，置位即 break，从而保留已出题目（ADR-0057 Q1=B）。
  bool _stopped = false;

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
    _fold = const QuestionGenFold();
    // 应出题数：各条规格 count 之和。流结束后据此校验「少题」——逐题串行出题时
    // 单题失败只会丢一条 STEP(status=error)，不做校验就会静默落库残缺任务。
    _expected = expectedQuestionCount(specs);
    _stopped = false;
    state = TaskGenPreview(_fold.questions, streaming: true, expected: _expected);
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
        // ADR-0057 Q1=B：家长主动停止 → 立即停在当前题边界，已出的题原样保留。
        // `await for` 的订阅会随之取消，底层 SSE 的 HTTP 连接被关闭（best-effort；
        // 服务端断连感知为已知缺口，见 ADR-0057 后端事项）。
        if (_stopped) break;
        _fold = _fold.apply(ev);
        if (_fold.hasError) {
          state = TaskGenError(_fold.errorText!);
          return;
        }
        state = TaskGenPreview(
          _fold.questions,
          streaming: true,
          expected: _expected,
          liveIndex: _fold.liveIndex,
          liveLabel: _fold.liveLabel,
          liveReasoning: _fold.liveReasoning,
          failures: _fold.failures,
          stage: _fold.stage,
        );
      }
      // UX 修正：流结束若 0 题，直接回显后端说明并跳过必败的落库请求，
      // 避免误触发后端 TASK_EMPTY_SPECS「请先生成题目再保存」。
      if (_fold.questions.isEmpty) {
        state = TaskGenError(_fold.emptyMessage);
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
        questions: _fold.questions,
        expected: _expected,
        failures: _fold.failures,
      );
      state = TaskGenReady(
        _fold.questions,
        expected: _expected,
        failures: _fold.failures,
        // 流自然结束：未主动停止（即便中途某题失败，也走上面的 hasError 分支）。
        stopped: _stopped,
      );
    } on AppException catch (e) {
      state = TaskGenError(e.message);
    } catch (e) {
      state = TaskGenError('⚠️ 网络异常，请稍后重试');
    }
  }

  /// 主动停止生成（ADR-0057）：客户端侧中断——保留已出题目并转为待确认态，
  /// 不再喂事件、不落库。与服务端是否立刻掐断当前那次 LLM 调用无关：本端只负责
  /// 立即停在当前题边界，已出的题交给家长决定确认或放弃。
  void stop() {
    if (state is! TaskGenPreview || !(state as TaskGenPreview).streaming) return;
    _stopped = true;
    state = TaskGenReady(
      _fold.questions,
      expected: _expected,
      failures: _fold.failures,
      stopped: true,
    );
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
