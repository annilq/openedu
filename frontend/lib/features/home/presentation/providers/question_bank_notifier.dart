import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../domain/repositories/question_bank_repository.dart';
import '../../providers/home_provider.dart';

// ── 题库视图状态机 ──
//
// 「加载列表」与「对选中项做动作」是两件事：前者是分页资源（首屏一页 + 触底追加），
// 后者是一次性动作（组卷 / 加入草稿 / 删除）。`Bank*` 各态沿用了这个划分——
// 动作态（BankActionLoading/Success/Error、BankDeleted）期间列表区显示加载占位，
// 动作结束后由 ref.listen 触发 _reload 回到 BankLoaded。
sealed class BankState {
  const BankState();
}
class BankIdle extends BankState {
  const BankIdle();
}
class BankLoading extends BankState {
  const BankLoading();
}

/// 已加载（至少一页）。[page] 是**累加后**的整页结果，不是最后一页。
class BankLoaded extends BankState {
  final CursorPage<BankQuestionItem> page;
  final int gradeSegment; // 当前年级 segment（-1 = 全部）
  final bool isLoadingMore;
  final String? moreError;
  const BankLoaded(
    this.page,
    this.gradeSegment, {
    this.isLoadingMore = false,
    this.moreError,
  });

  BankLoaded copyWith({
    CursorPage<BankQuestionItem>? page,
    bool? isLoadingMore,
    Object? moreError = _sentinel,
  }) =>
      BankLoaded(
        page ?? this.page,
        gradeSegment,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        moreError: identical(moreError, _sentinel)
            ? this.moreError
            : moreError as String?,
      );
}

/// [copyWith] 的「不改动」哨兵：``moreError`` 允许显式传 null 清空。
const Object _sentinel = Object();

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

class BankDeleted extends BankState {
  final int deleted;
  final int skippedInUse;
  final int skippedForbidden;
  const BankDeleted(this.deleted, this.skippedInUse, this.skippedForbidden);
}

class QuestionBankNotifier extends StateNotifier<BankState> {
  final QuestionBankRepository _repo;
  QuestionBankNotifier(this._repo) : super(const BankIdle());

  /// 当前筛选条件：[loadMore] 没处再传一遍，取下一页时必须沿用同一组过滤。
  int _gradeSegment = -1;
  String? _subject;
  String? _qtype;
  String? _keyword;

  bool _inFlight = false;

  Future<void> load({
    int gradeSegment = -1,
    String? subject,
    String? qtype,
    String? keyword,
  }) async {
    _gradeSegment = gradeSegment;
    _subject = subject;
    _qtype = qtype;
    _keyword = keyword;
    _inFlight = true;
    state = const BankLoading();
    try {
      final page = await _repo.getQuestions(
        subject: subject,
        grade: gradeSegment < 0 ? null : gradeSegment,
        qtype: qtype,
        keyword: keyword,
      );
      state = BankLoaded(page, gradeSegment);
    } catch (e) {
      state = BankError(e.toString());
    } finally {
      _inFlight = false;
    }
  }

  /// 追加下一页（触底 / 点「加载更多」）。
  ///
  /// 三道闸：没到尾、没有请求在飞、当前确实是已加载态。快速滑动会连发触底回调，
  /// 少了任何一道都会取到重复页。
  Future<void> loadMore() async {
    final before = state;
    if (before is! BankLoaded ||
        !before.page.hasMore ||
        _inFlight ||
        before.page.nextCursor == null) {
      return;
    }
    _inFlight = true;
    state = before.copyWith(isLoadingMore: true, moreError: null);
    try {
      final next = await _repo.getQuestions(
        subject: _subject,
        grade: _gradeSegment < 0 ? null : _gradeSegment,
        qtype: _qtype,
        keyword: _keyword,
        cursor: before.page.nextCursor,
      );
      final current = state;
      if (current is! BankLoaded) return; // 期间筛选条件变了 / 重新加载过
      state = BankLoaded(current.page.append(next), current.gradeSegment);
    } catch (e) {
      final current = state;
      if (current is! BankLoaded) return;
      state = current.copyWith(isLoadingMore: false, moreError: e.toString());
    } finally {
      _inFlight = false;
    }
  }

  /// 选项 B 草稿选择器：拉取家长草稿列表。
  Future<List<TaskModel>> fetchDraftTasks() async {
    return await _repo.getDraftTasks();
  }

  /// 反查某题库题被哪些任务引用（闭环「用过 N 次 → 在哪里用」）。
  Future<List<QuestionUsageItem>> fetchQuestionUsages(String questionId) async {
    return await _repo.getQuestionUsages(questionId);
  }

  /// 按 id 拉取完整任务，供引用列表跳转复核页。
  Future<TaskModel> fetchTaskById(String taskId) async {
    return await _repo.getTaskById(taskId);
  }

  void reset() => state = const BankIdle();

  Future<void> createTaskFromBank({
    required String title,
    required String childId,
    required List<String> ids,
  }) async {
    state = const BankActionLoading();
    try {
      final task = await _repo.createTaskFromBank(
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
      final task = await _repo.addToTaskFromBank(taskId: taskId, questionIds: ids);
      state = BankActionSuccess(task);
    } catch (e) {
      state = BankActionError(e.toString());
    }
  }

  Future<void> deleteQuestions(List<String> ids) async {
    state = const BankActionLoading();
    try {
      final res = await _repo.deleteQuestions(ids);
      state = BankDeleted(
        res.deleted.length,
        res.skippedInUse.length,
        res.skippedForbidden.length,
      );
    } catch (e) {
      state = BankActionError(e.toString());
    }
  }
}

final questionBankNotifierProvider =
    StateNotifierProvider<QuestionBankNotifier, BankState>((ref) {
  return QuestionBankNotifier(ref.watch(questionBankRepositoryProvider));
});
