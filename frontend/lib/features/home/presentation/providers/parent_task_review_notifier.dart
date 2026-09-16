import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/exceptions/app_exception.dart';
import '../../../assistant/domain/assistant_event.dart';
import '../../../assistant/domain/repositories/assistant_repository.dart';
import '../../../assistant/providers/assistant_provider.dart';
import '../../domain/repositories/task_review_repository.dart';
import '../../providers/home_provider.dart';

// ───────── 草稿题审核状态机 ─────────
sealed class ReviewState {
  const ReviewState();
}

class ReviewLoading extends ReviewState {
  const ReviewLoading();
}

class ReviewLoaded extends ReviewState {
  final TaskModel task;

  /// 正在执行单题动作（删除/编辑/换一题/加入题库）的 TaskQuestion id。
  ///
  /// 非空即该卡片进入「处理中」：按钮全部禁用并显示 spinner。此前这些动作没有任何
  /// 进行中反馈——换一题是一次同步 LLM 调用，家长连点会并发多个请求，且后返回的
  /// 会用它自己开始时那份快照覆盖 state（丢更新）。
  final String? busyTqId;

  /// 整卷级动作（整卷重生成）的进行中进度文案，如「正在生成第 2/5 题…」。
  ///
  /// 非空时整页进入整卷 busy：操作栏与所有题卡一并禁用。此前整卷重生成只切到
  /// 整页 ReviewLoading——整页白屏转圈，家长既看不到进度也看不到原题。
  final String? progress;

  /// 模型正在产出的实时文本（THINKING 帧累加），如「先定情境…再配干扰项…」。
  ///
  /// 只有进度文案没有它，家长看到的就是「生成中」三个字干等十几秒——这也是这次
  /// 流式改造要真正交付的东西：底层出题管线本来就逐段吐推理文本，此前被同步
  /// drain 版吞掉了。新题卡/新阶段到达时由 notifier 清空。
  final String liveText;

  const ReviewLoaded(
    this.task, {
    this.busyTqId,
    this.progress,
    this.liveText = '',
  });

  /// 任一题目正在处理：顶部整卷级操作（整卷重生成/一键入库/作废/锁定）也应禁用。
  bool get anyBusy => busyTqId != null || progress != null;
}

class ReviewError extends ReviewState {
  final String message;
  final String? code;
  const ReviewError(this.message, {this.code});
}

class ReviewNotifier extends StateNotifier<ReviewState> {
  final TaskReviewRepository _review;
  final AssistantRepository _assistant;
  ReviewNotifier(this._review, this._assistant, {TaskModel? initial})
      : super(initial == null
            ? const ReviewLoading()
            : ReviewLoaded(initial));

  /// 从后端刷新当前 Task（含完整题目列表）。
  Future<void> load(String taskId) async {
    state = const ReviewLoading();
    try {
      state = ReviewLoaded(await _review.load(taskId));
    } catch (e) {
      state = ReviewError(
        e.toString(),
        code: e is Exception ? null : null,
      );
    }
  }

  /// R-Q3：单题加入题库。
  Future<void> promoteOne({
    required String taskId,
    required String tqId,
  }) async {
    final cur = state;
    if (cur is! ReviewLoaded || cur.anyBusy) return;
    state = ReviewLoaded(cur.task, busyTqId: tqId);
    try {
      final updatedQ = await _review.promoteOne(taskId: taskId, tqId: tqId);
      state = ReviewLoaded(_replace(cur.task, tqId, updatedQ));
    } catch (e) {
      state = ReviewLoaded(cur.task);
      rethrow;
    }
  }

  /// 一键把所有未入库的题批量 promote。
  Future<void> promoteAll(String taskId) async {
    final cur = state;
    if (cur is! ReviewLoaded || cur.anyBusy) return;
    try {
      state = ReviewLoaded(await _review.promoteAll(taskId));
    } catch (e) {
      rethrow;
    }
  }

  /// 单题重生成（流式）。
  ///
  /// 走 `POST /tasks/{id}/questions/{tq}/regenerate-stream`（SSE）：一次 LLM 调用常常
  /// 超过普通请求的 30 秒 receiveTimeout，同步版会被超时掐断、且期间无进度反馈。
  /// 帧协议与整卷生成一致，这里只取 DATA(question) 与 ERROR 两帧。
  Future<void> regenerateOne({
    required String taskId,
    required String tqId,
  }) async {
    final cur = state;
    if (cur is! ReviewLoaded || cur.anyBusy) return;
    state = ReviewLoaded(cur.task, busyTqId: tqId);
    try {
      QuestionModel? updated;
      var live = '';
      await for (final ev
          in _assistant.regenerateOne(taskId: taskId, tqId: tqId)) {
        if (ev.eventType == AssistantEventType.error) {
          throw AppException(ev.message ?? '换一题失败，请稍后重试');
        }
        if (ev.eventType == AssistantEventType.thinking) {
          live += ev.text ?? '';
          state = ReviewLoaded(cur.task, busyTqId: tqId, liveText: live);
        }
        if (ev.eventType == AssistantEventType.data &&
            ev.data?['type'] == 'question') {
          final result = ev.data?['result'];
          if (result is Map<String, dynamic>) {
            updated = QuestionModel.fromJson(result);
          }
        }
      }
      if (updated == null) {
        throw AppException('换一题失败：本次没有生成新题目');
      }
      state = ReviewLoaded(_replace(cur.task, tqId, updated));
    } catch (e) {
      state = ReviewLoaded(cur.task);
      rethrow;
    }
  }

  /// 整卷重生成（按 Task.specs 原规格，流式）。
  ///
  /// 同步版要把整卷 N 道题全部出完才返回（2 题就 19–36 秒），必然撞上普通请求的
  /// 30 秒 receiveTimeout。改走 `POST /tasks/{id}/regenerate-stream` 后：复用流式
  /// 端点的长超时，并把后端的 STEP 进度帧（「正在生成第 i/N 题…」）直接透到
  /// [ReviewLoaded.progress]，家长能实时看到推进而不是整页白屏转圈。
  Future<void> regenerateAll(String taskId) async {
    final cur = state;
    if (cur is! ReviewLoaded || cur.anyBusy) return;
    const initialProgress = '正在重生成整卷…';
    state = ReviewLoaded(cur.task, progress: initialProgress);
    try {
      TaskModel? updated;
      var progress = initialProgress;
      var live = '';
      await for (final ev in _assistant.regenerateAll(taskId: taskId)) {
        if (ev.eventType == AssistantEventType.error) {
          throw AppException(ev.message ?? '整卷重生成失败，请稍后重试');
        }
        if (ev.eventType == AssistantEventType.step && ev.label != null) {
          // 新阶段（下一题 / 落库）清空上一题的推理文本，避免越堆越长。
          progress = ev.label!;
          live = '';
          state = ReviewLoaded(cur.task, progress: progress);
        }
        if (ev.eventType == AssistantEventType.thinking) {
          live += ev.text ?? '';
          state = ReviewLoaded(cur.task, progress: progress, liveText: live);
        }
        if (ev.eventType == AssistantEventType.data &&
            ev.data?['type'] == 'task') {
          final result = ev.data?['result'];
          if (result is Map<String, dynamic>) {
            updated = TaskModel.fromJson(result);
          }
        }
      }
      if (updated == null) {
        throw AppException('整卷重生成失败：本次没有返回题目');
      }
      state = ReviewLoaded(updated);
    } catch (e) {
      state = ReviewLoaded(cur.task);
      rethrow;
    }
  }

  /// R-Q5=b：删除草稿项，级联删 Question（若已入题库）。
  Future<void> removeOne({
    required String taskId,
    required String tqId,
  }) async {
    final cur = state;
    if (cur is! ReviewLoaded || cur.anyBusy) return;
    state = ReviewLoaded(cur.task, busyTqId: tqId);
    try {
      await _review.removeOne(taskId: taskId, tqId: tqId);
      // 允许删到 0 题：草稿清空后走空态引导（整卷重生成 / 返回题库重新组卷），
      // 比「最后一题点不动且无任何提示」更可预期。
      final task = cur.task.copyWith(
        questions: cur.task.questions.where((q) => q.id != tqId).toList(),
      );
      state = ReviewLoaded(task);
    } catch (e) {
      state = ReviewLoaded(cur.task);
      rethrow;
    }
  }

  /// R-Q4：编辑草稿快照题（仅 stem/options/answer/explanation 四字段）。
  Future<void> editOne({
    required String taskId,
    required String tqId,
    required Map<String, dynamic> edits,
  }) async {
    final cur = state;
    if (cur is! ReviewLoaded || cur.anyBusy) return;
    state = ReviewLoaded(cur.task, busyTqId: tqId);
    try {
      final updatedQ =
          await _review.editOne(taskId: taskId, tqId: tqId, edits: edits);
      state = ReviewLoaded(_replace(cur.task, tqId, updatedQ));
    } catch (e) {
      state = ReviewLoaded(cur.task);
      rethrow;
    }
  }

  /// 编辑任务元信息（仅 draft 态；当前仅标题）。
  ///
  /// busy 用哨兵 id 'meta'：`anyBusy` 生效 → 整卷级操作禁用；但 `busyTqId == q.id`
  /// 不命中任何题卡 → 各题卡保持可用（元信息编辑与题目内容互不相干）。
  Future<void> editMeta({
    required String taskId,
    required String title,
  }) async {
    final cur = state;
    if (cur is! ReviewLoaded || cur.anyBusy) return;
    state = ReviewLoaded(cur.task, busyTqId: 'meta');
    try {
      final updated = await _review
          .editMeta(taskId: taskId, edits: {'title': title});
      state = ReviewLoaded(updated);
    } catch (e) {
      state = ReviewLoaded(cur.task);
      rethrow;
    }
  }

  /// 锁定草稿成卷（R-Q1=c 自动 promote-all）。
  Future<TaskModel> confirm(String taskId) async {
    final updated = await _review.confirm(taskId);
    state = ReviewLoaded(updated);
    return updated;
  }

  /// 派发给指定娃娃。
  Future<TaskModel> assign({
    required String taskId,
    required String childId,
  }) async {
    final updated = await _review.assign(taskId: taskId, childId: childId);
    state = ReviewLoaded(updated);
    return updated;
  }

  /// 作废草稿（R-Q5=b，级联删 Question）。
  Future<void> discard(String taskId) => _review.discard(taskId);

  // -------- helpers --------

  TaskModel _replace(TaskModel task, String tqId, QuestionModel updated) {
    return task.copyWith(
      questions: task.questions
          .map((q) => q.id == tqId ? updated : q)
          .toList(),
    );
  }
}

/// 以 taskId 为 key 的 Family 提供器，避免多个草稿页共享状态。
final parentTaskReviewProvider = StateNotifierProvider.family<
    ReviewNotifier,
    ReviewState,
    TaskModel>((ref, initialTask) {
  return ReviewNotifier(
    ref.watch(taskReviewRepositoryProvider),
    ref.watch(assistantRepositoryProvider),
    initial: initialTask,
  );
});
