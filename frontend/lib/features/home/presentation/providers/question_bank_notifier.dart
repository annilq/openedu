import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../data/datasource/question_bank_remote_data_source.dart';

// ── 题库视图状态机 ──
sealed class BankState {
  const BankState();
}
class BankIdle extends BankState {
  const BankIdle();
}
class BankLoading extends BankState {
  const BankLoading();
}
class BankLoaded extends BankState {
  final BankListResp data;
  final int gradeSegment; // 当前年级 segment（-1 = 全部）
  const BankLoaded(this.data, this.gradeSegment);
}
class BankError extends BankState {
  final String message;
  const BankError(this.message);
}
class BankActionLoading extends BankState {
  const BankActionLoading();
}
class BankActionSuccess extends BankState {
  final TaskModel task;
  const BankActionSuccess(this.task);
}
class BankActionError extends BankState {
  final String message;
  const BankActionError(this.message);
}

class QuestionBankNotifier extends StateNotifier<BankState> {
  final QuestionBankRemoteDataSource _ds;
  QuestionBankNotifier(this._ds) : super(const BankIdle());

  Future<void> load({
    int gradeSegment = -1,
    String? subject,
    String? qtype,
    String? keyword,
  }) async {
    state = const BankLoading();
    try {
      final data = await _ds.getQuestions(
        subject: subject,
        grade: gradeSegment < 0 ? null : gradeSegment,
        qtype: qtype,
        keyword: keyword,
        page: 1,
      );
      state = BankLoaded(data, gradeSegment);
    } catch (e) {
      state = BankError(e.toString());
    }
  }

  /// 选项 B 草稿选择器：拉取家长草稿列表。
  Future<List<TaskModel>> fetchDraftTasks() async {
    return await _ds.getDraftTasks();
  }

  void reset() => state = const BankIdle();

  Future<void> createTaskFromBank({
    required String title,
    required String childId,
    required List<String> ids,
  }) async {
    state = const BankActionLoading();
    try {
      final task = await _ds.createTaskFromBank(
        title: title,
        childId: childId,
        questionIds: ids,
      );
      state = BankActionSuccess(task);
    } catch (e) {
      state = BankActionError(e.toString());
    }
  }

  Future<void> addToTaskFromBank({
    required String taskId,
    required List<String> ids,
  }) async {
    state = const BankActionLoading();
    try {
      final task = await _ds.addToTaskFromBank(taskId: taskId, questionIds: ids);
      state = BankActionSuccess(task);
    } catch (e) {
      state = BankActionError(e.toString());
    }
  }
}

final questionBankNotifierProvider =
    StateNotifierProvider<QuestionBankNotifier, BankState>((ref) {
  final ds = QuestionBankRemoteDataSource(ref.watch(networkServiceProvider));
  return QuestionBankNotifier(ds);
});
