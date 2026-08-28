import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';

// ───────── 草稿题审核状态机 ─────────
sealed class ReviewState {
  const ReviewState();
}

class ReviewLoading extends ReviewState {
  const ReviewLoading();
}

class ReviewLoaded extends ReviewState {
  final TaskModel task;
  const ReviewLoaded(this.task);
}

class ReviewError extends ReviewState {
  final String message;
  final String? code;
  const ReviewError(this.message, {this.code});
}

class ReviewNotifier extends StateNotifier<ReviewState> {
  final NetworkService _network;
  ReviewNotifier(this._network, {TaskModel? initial})
      : super(initial == null
            ? const ReviewLoading()
            : ReviewLoaded(initial));

  /// 从后端刷新当前 Task（含完整题目列表）。
  Future<void> load(String taskId) async {
    state = const ReviewLoading();
    try {
      final data = await _network.get('/tasks/$taskId');
      state = ReviewLoaded(TaskModel.fromJson(data));
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
    if (cur is! ReviewLoaded) return;
    try {
      final data = await _network
          .post('/tasks/$taskId/questions/$tqId/promote');
      final updatedQ = QuestionModel.fromJson(data);
      state = ReviewLoaded(_replace(cur.task, tqId, updatedQ));
    } catch (e) {
      rethrow;
    }
  }

  /// 一键把所有未入库的题批量 promote。
  Future<void> promoteAll(String taskId) async {
    final cur = state;
    if (cur is! ReviewLoaded) return;
    try {
      final data = await _network.post('/tasks/$taskId/promote-all');
      state = ReviewLoaded(TaskModel.fromJson(data));
    } catch (e) {
      rethrow;
    }
  }

  /// 单题重生成。
  Future<void> regenerateOne({
    required String taskId,
    required String tqId,
  }) async {
    final cur = state;
    if (cur is! ReviewLoaded) return;
    try {
      final data = await _network
          .post('/tasks/$taskId/questions/$tqId/regenerate');
      final updatedQ = QuestionModel.fromJson(data);
      state = ReviewLoaded(_replace(cur.task, tqId, updatedQ));
    } catch (e) {
      rethrow;
    }
  }

  /// 整卷重生成（按 Task.specs 原规格）。
  Future<void> regenerateAll(String taskId) async {
    final cur = state;
    if (cur is! ReviewLoaded) return;
    state = const ReviewLoading();
    try {
      final data = await _network.post('/tasks/$taskId/regenerate');
      state = ReviewLoaded(TaskModel.fromJson(data));
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
    if (cur is! ReviewLoaded) return;
    try {
      await _network.delete('/tasks/$taskId/questions/$tqId');
      final task = cur.task.copyWith(
        questions: cur.task.questions.where((q) => q.id != tqId).toList(),
      );
      state = ReviewLoaded(task);
    } catch (e) {
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
    if (cur is! ReviewLoaded) return;
    try {
      final data = await _network.put(
        '/tasks/$taskId/questions/$tqId',
        body: edits,
      );
      final updatedQ = QuestionModel.fromJson(data);
      state = ReviewLoaded(_replace(cur.task, tqId, updatedQ));
    } catch (e) {
      rethrow;
    }
  }

  /// 锁定草稿成卷（R-Q1=c 自动 promote-all）。
  Future<TaskModel> confirm(String taskId) async {
    final data = await _network.post('/tasks/$taskId/confirm');
    final updated = TaskModel.fromJson(data);
    state = ReviewLoaded(updated);
    return updated;
  }

  /// 派发给指定娃娃。
  Future<TaskModel> assign({
    required String taskId,
    required String childId,
  }) async {
    final data = await _network
        .post('/tasks/$taskId/assign?child_id=$childId');
    final updated = TaskModel.fromJson(data);
    state = ReviewLoaded(updated);
    return updated;
  }

  /// 作废草稿（R-Q5=b，级联删 Question）。
  Future<void> discard(String taskId) async {
    await _network.delete('/tasks/$taskId');
  }

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
  final network = ref.watch(networkServiceProvider);
  return ReviewNotifier(network, initial: initialTask);
});
