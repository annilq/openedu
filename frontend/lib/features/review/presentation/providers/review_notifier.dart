import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/presentation/paging.dart';
import '../../domain/repositories/review_repository.dart';
import '../../providers/review_provider.dart';

/// 复习作答：与练习一致的批改结果（错题调度更新由后端完成）。
typedef ReviewAnswerResult = AnswerResultModel;

// —— 娃娃端：待复习队列 ——
sealed class DueReviewState {
  const DueReviewState();
}

class DueReviewInitial extends DueReviewState {
  const DueReviewInitial();
}

class DueReviewLoading extends DueReviewState {
  const DueReviewLoading();
}

class DueReviewLoaded extends DueReviewState {
  final List<ReviewItemModel> items;
  const DueReviewLoaded(this.items);
}

class DueReviewError extends DueReviewState {
  final String message;
  const DueReviewError(this.message);
}

class DueReviewNotifier extends StateNotifier<DueReviewState> {
  final ReviewRepository _repo;
  DueReviewNotifier(this._repo) : super(const DueReviewInitial());

  Future<void> load() async {
    state = const DueReviewLoading();
    try {
      state = DueReviewLoaded(await _repo.dueReview());
    } catch (e) {
      state = DueReviewError(e.toString());
    }
  }

  /// 提交一道复习作答；成功后从当前队列移除该题（无论对错，下一轮到期重新进入）。
  Future<ReviewAnswerResult?> answer(String wrongQuestionId, String studentAnswer) async {
    final current = state;
    if (current is! DueReviewLoaded) return null;
    try {
      final result = await _repo.answer(wrongQuestionId, studentAnswer);
      final remaining = current.items
          .where((i) => i.wrongQuestionId != wrongQuestionId)
          .toList();
      state = DueReviewLoaded(remaining);
      return result;
    } catch (e) {
      state = DueReviewError(e.toString());
      return null;
    }
  }
}

final dueReviewNotifierProvider =
    StateNotifierProvider<DueReviewNotifier, DueReviewState>((ref) {
  return DueReviewNotifier(ref.watch(reviewRepositoryProvider));
});

// —— 错题本：娃娃自查 / 家长查看（游标分页，ADR-0053）——
//
// 错题本会一直长（答错即入集），一次拉全量会让家长端几百张卡全部构建出来。
// 改成首屏一页 + 触底追加后，卡片构建与网络载荷都随视口走。
/// 娃娃自查：错题本（不含答案）。
final childWrongQuestionsProvider = StateNotifierProvider<
    PagingNotifier<WrongQuestionModel>, PagingState<WrongQuestionModel>>(
  (ref) => PagingNotifier<WrongQuestionModel>(
    ({cursor}) => ref
        .watch(reviewRepositoryProvider)
        .childWrongQuestions(cursor: cursor),
  ),
);

/// 家长查看某娃娃的错题本（含答案）。
final parentWrongQuestionsProvider = StateNotifierProvider<
    ParamPagingNotifier<WrongQuestionModel, String>,
    PagingState<WrongQuestionModel>>(
  (ref) => ParamPagingNotifier<WrongQuestionModel, String>(
    (childId, {cursor}) => ref
        .watch(reviewRepositoryProvider)
        .parentWrongQuestions(childId, cursor: cursor),
  ),
);
